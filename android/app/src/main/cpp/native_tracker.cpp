#include <jni.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <libusb.h>
#include <libuvc/libuvc.h>

namespace {

JavaVM * g_vm = nullptr;
jclass g_main_activity_class = nullptr;
jmethodID g_dispatch_event = nullptr;

std::atomic<bool> g_running{false};
std::thread g_worker;
std::mutex g_state_mutex;
int g_usb_fd = -1;
int g_usb_vid = 0;
int g_usb_pid = 0;
libusb_context * g_usb_ctx = nullptr;
uvc_context_t * g_uvc_ctx = nullptr;
uvc_device_handle_t * g_uvc_devh = nullptr;
std::atomic<bool> g_uvc_streaming{false};
std::atomic<uint64_t> g_stream_frame_count{0};
std::atomic<uint64_t> g_stream_byte_count{0};
std::atomic<bool> g_usb_events_running{false};
std::thread g_usb_events_thread;
std::mutex g_frame_mutex;
std::vector<uint8_t> g_latest_yuyv;
int g_latest_width = 0;
int g_latest_height = 0;
int g_latest_format = 0; // 0=none, 1=YUYV, 2=MJPEG

float g_kp_x = 0.015f;
float g_ki_x = 0.0f;
float g_kd_x = 0.004f;
float g_kp_y = 0.015f;
float g_ki_y = 0.0f;
float g_kd_y = 0.004f;
std::string g_target_policy = "largest";

void send_event(const std::string & type, const std::string & payload) {
    if (g_vm == nullptr || g_main_activity_class == nullptr || g_dispatch_event == nullptr) {
        return;
    }
    JNIEnv * env = nullptr;
    bool did_attach = false;
    if (g_vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
        if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            return;
        }
        did_attach = true;
    }

    jstring j_type = env->NewStringUTF(type.c_str());
    jstring j_payload = env->NewStringUTF(payload.c_str());
    env->CallStaticVoidMethod(g_main_activity_class, g_dispatch_event, j_type, j_payload);
    env->DeleteLocalRef(j_type);
    env->DeleteLocalRef(j_payload);

    if (did_attach) {
        g_vm->DetachCurrentThread();
    }
}

void emit_state(const std::string & status, const std::string & message) {
    std::ostringstream out;
    out << "{\"status\":\"" << status << "\",\"message\":\"" << message << "\"}";
    send_event("state", out.str());
}

void on_uvc_frame(uvc_frame_t * frame, void *) {
    if (!g_uvc_streaming.load() || frame == nullptr) {
        return;
    }
    g_stream_frame_count.fetch_add(1, std::memory_order_relaxed);
    g_stream_byte_count.fetch_add(static_cast<uint64_t>(frame->data_bytes), std::memory_order_relaxed);
    if ((frame->frame_format == UVC_FRAME_FORMAT_YUYV || frame->frame_format == UVC_FRAME_FORMAT_MJPEG) &&
        frame->data != nullptr &&
        frame->data_bytes > 0) {
        std::lock_guard<std::mutex> lock(g_frame_mutex);
        g_latest_width = static_cast<int>(frame->width);
        g_latest_height = static_cast<int>(frame->height);
        g_latest_yuyv.resize(frame->data_bytes);
        std::memcpy(g_latest_yuyv.data(), frame->data, frame->data_bytes);
        g_latest_format = (frame->frame_format == UVC_FRAME_FORMAT_YUYV) ? 1 : 2;
    }
}

void stop_usb_events_locked() {
    if (!g_usb_events_running.exchange(false)) {
        return;
    }
    if (g_usb_events_thread.joinable()) {
        g_usb_events_thread.join();
    }
}

void start_usb_events_locked() {
    if (g_usb_ctx == nullptr || g_usb_events_running.load()) {
        return;
    }
    g_usb_events_running.store(true);
    g_usb_events_thread = std::thread([]() {
        while (g_usb_events_running.load()) {
            if (g_usb_ctx == nullptr) {
                break;
            }
            timeval timeout{};
            timeout.tv_sec = 0;
            timeout.tv_usec = 100000;
            const int rc = libusb_handle_events_timeout_completed(g_usb_ctx, &timeout, nullptr);
            if (rc == LIBUSB_ERROR_INTERRUPTED) {
                continue;
            }
            if (rc < 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        }
    });
}

void shutdown_uvc_locked() {
    if (g_uvc_streaming.exchange(false) && g_uvc_devh != nullptr) {
        uvc_stop_streaming(g_uvc_devh);
    }
    stop_usb_events_locked();
    if (g_uvc_devh != nullptr) {
        uvc_close(g_uvc_devh);
        g_uvc_devh = nullptr;
    }
    if (g_uvc_ctx != nullptr) {
        uvc_exit(g_uvc_ctx);
        g_uvc_ctx = nullptr;
    }
    if (g_usb_ctx != nullptr) {
        libusb_exit(g_usb_ctx);
        g_usb_ctx = nullptr;
    }
    g_stream_frame_count.store(0, std::memory_order_relaxed);
    g_stream_byte_count.store(0, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(g_frame_mutex);
        g_latest_yuyv.clear();
        g_latest_width = 0;
        g_latest_height = 0;
        g_latest_format = 0;
    }
}

bool init_uvc_from_fd_locked(int fd) {
    shutdown_uvc_locked();
    if (fd < 0) {
        return false;
    }

    libusb_init_option options[1]{};
    options[0].option = LIBUSB_OPTION_NO_DEVICE_DISCOVERY;
    options[0].value.ival = 1;
    int rc = libusb_init_context(&g_usb_ctx, options, 1);
    if (rc != LIBUSB_SUCCESS || g_usb_ctx == nullptr) {
        std::ostringstream out;
        out << "libusb_init_context failed: " << rc << " (" << libusb_error_name(rc) << ")";
        emit_state("error", out.str());
        shutdown_uvc_locked();
        return false;
    }
    const uvc_error_t init_rc = uvc_init(&g_uvc_ctx, g_usb_ctx);
    if (init_rc != UVC_SUCCESS || g_uvc_ctx == nullptr) {
        std::ostringstream out;
        out << "uvc_init failed: " << init_rc;
        emit_state("error", out.str());
        shutdown_uvc_locked();
        return false;
    }

    const uvc_error_t wrap_rc = uvc_wrap(fd, g_uvc_ctx, &g_uvc_devh);
    if (wrap_rc != UVC_SUCCESS || g_uvc_devh == nullptr) {
        std::ostringstream out;
        out << "uvc_wrap(fd) failed: " << wrap_rc;
        emit_state("error", out.str());
        shutdown_uvc_locked();
        return false;
    }

    emit_state("connected", "Native UVC handle ready.");
    return true;
}

bool start_uvc_stream_locked() {
    if (g_uvc_streaming.load()) {
        return true;
    }
    if (g_uvc_devh == nullptr) {
        emit_state("error", "UVC device is not ready.");
        return false;
    }

    struct Attempt {
        uvc_frame_format format;
        int width;
        int height;
        int fps;
        const char * label;
    };
    const Attempt attempts[] = {
        {UVC_FRAME_FORMAT_MJPEG, 640, 480, 30, "mjpeg_480p30"},
        {UVC_FRAME_FORMAT_MJPEG, 1280, 720, 30, "mjpeg_720p30"},
        {UVC_FRAME_FORMAT_MJPEG, 1920, 1080, 30, "mjpeg_1080p30"},
        {UVC_FRAME_FORMAT_YUYV, 640, 480, 30, "yuyv_480p30"},
        {UVC_FRAME_FORMAT_ANY, 640, 480, 30, "any_480p30"},
    };

    uvc_stream_ctrl_t ctrl{};
    const Attempt * chosen = nullptr;
    for (const auto & attempt : attempts) {
        const uvc_error_t ctrl_rc = uvc_get_stream_ctrl_format_size(
            g_uvc_devh,
            &ctrl,
            attempt.format,
            attempt.width,
            attempt.height,
            attempt.fps);
        if (ctrl_rc == UVC_SUCCESS) {
            chosen = &attempt;
            break;
        }
    }
    if (chosen == nullptr) {
        emit_state("error", "No compatible UVC stream profile.");
        return false;
    }

    const uvc_error_t stream_rc = uvc_start_streaming(g_uvc_devh, &ctrl, on_uvc_frame, nullptr, 0);
    if (stream_rc != UVC_SUCCESS) {
        std::ostringstream out;
        out << "uvc_start_streaming failed: " << stream_rc;
        emit_state("error", out.str());
        return false;
    }

    start_usb_events_locked();
    g_stream_frame_count.store(0, std::memory_order_relaxed);
    g_stream_byte_count.store(0, std::memory_order_relaxed);
    g_uvc_streaming.store(true);

    std::ostringstream msg;
    msg << "Native UVC stream active (" << chosen->label << ").";
    emit_state("connected", msg.str());
    return true;
}

void worker_loop() {
    emit_state("running", "Native tracking loop started (stream telemetry only).");
    auto last_stream_report = std::chrono::steady_clock::now();
    while (g_running.load()) {
        const auto stream_now = std::chrono::steady_clock::now();
        const auto stream_elapsed_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(stream_now - last_stream_report).count();
        if (stream_elapsed_ms >= 1000) {
            const uint64_t frames =
                g_stream_frame_count.exchange(0, std::memory_order_relaxed);
            const uint64_t bytes =
                g_stream_byte_count.exchange(0, std::memory_order_relaxed);
            const double kbps =
                stream_elapsed_ms > 0 ? (static_cast<double>(bytes) * 8.0 / stream_elapsed_ms) : 0.0;
            std::ostringstream stream;
            stream.setf(std::ios::fixed);
            stream.precision(3);
            stream << "{\"frames\":" << frames << ",\"bytes\":" << bytes << ",\"kbps\":" << kbps
                   << ",\"source\":\"libuvc\"}";
            send_event("stream", stream.str());
            last_stream_report = stream_now;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(40));
    }
    emit_state("connected", "Native tracker stopped.");
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeInit(JNIEnv *, jobject) {
    emit_state("ready", "Native tracker initialized.");
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeAttachUsbFd(
    JNIEnv *,
    jobject,
    jint fd,
    jint vid,
    jint pid) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_usb_fd = fd;
    g_usb_vid = vid;
    g_usb_pid = pid;
    const bool ok = init_uvc_from_fd_locked(g_usb_fd);

    std::ostringstream msg;
    msg << "{\"status\":\"" << (ok ? "connected" : "error") << "\",\"message\":\"USB attached (fd="
        << g_usb_fd << ", vid=0x" << std::hex << g_usb_vid << ", pid=0x" << g_usb_pid
        << ", nativeUvc=" << (ok ? "ok" : "failed") << ").\"}";
    send_event("state", msg.str());
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeActivateCamera(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_usb_fd < 0) {
        emit_state("error", "No USB device attached.");
        return JNI_FALSE;
    }
    if (g_uvc_devh == nullptr && !init_uvc_from_fd_locked(g_usb_fd)) {
        return JNI_FALSE;
    }
    return start_uvc_stream_locked() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeDetachUsb(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_usb_fd = -1;
    g_usb_vid = 0;
    g_usb_pid = 0;
    shutdown_uvc_locked();
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeStartTracking(JNIEnv *, jobject) {
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_usb_fd < 0) {
            emit_state("error", "No USB device attached.");
            return JNI_FALSE;
        }
        if (g_uvc_devh == nullptr && !init_uvc_from_fd_locked(g_usb_fd)) {
            return JNI_FALSE;
        }
        if (!start_uvc_stream_locked()) {
            return JNI_FALSE;
        }
    }
    if (g_running.exchange(true)) {
        return JNI_TRUE;
    }
    g_worker = std::thread(worker_loop);
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeStopTracking(JNIEnv *, jobject) {
    if (!g_running.exchange(false)) {
        return JNI_TRUE;
    }
    if (g_worker.joinable()) {
        g_worker.join();
    }
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeSetPid(
    JNIEnv *,
    jobject,
    jfloat kp_x,
    jfloat ki_x,
    jfloat kd_x,
    jfloat kp_y,
    jfloat ki_y,
    jfloat kd_y) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_kp_x = kp_x;
    g_ki_x = ki_x;
    g_kd_x = kd_x;
    g_kp_y = kp_y;
    g_ki_y = ki_y;
    g_kd_y = kd_y;
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeSetTargetPolicy(
    JNIEnv * env,
    jobject,
    jstring mode) {
    const char * raw = env->GetStringUTFChars(mode, nullptr);
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        g_target_policy = raw == nullptr ? "largest" : raw;
    }
    if (raw != nullptr) {
        env->ReleaseStringUTFChars(mode, raw);
    }
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeManualControl(
    JNIEnv *,
    jobject,
    jfloat pan,
    jfloat tilt,
    jint duration_ms) {
    std::ostringstream telemetry;
    telemetry.setf(std::ios::fixed);
    telemetry.precision(3);
    telemetry << "{\"fps\":0.0,\"latencyMs\":0.0,\"pan\":" << pan << ",\"tilt\":" << tilt << "}";
    send_event("telemetry", telemetry.str());

    std::ostringstream state;
    state << "{\"status\":\"connected\",\"message\":\"Manual control pan=" << pan << ", tilt="
          << tilt << ", durationMs=" << duration_ms << "\"}";
    send_event("state", state.str());
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeDispose(JNIEnv *, jobject) {
    if (g_running.exchange(false) && g_worker.joinable()) {
        g_worker.join();
    }
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        g_usb_fd = -1;
        g_usb_vid = 0;
        g_usb_pid = 0;
        shutdown_uvc_locked();
    }
    emit_state("idle", "Native tracker disposed.");
    return JNI_TRUE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeGetLatestYuyvFrame(
    JNIEnv * env,
    jobject) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    if (g_latest_yuyv.empty()) {
        return nullptr;
    }
    jbyteArray out = env->NewByteArray(static_cast<jsize>(g_latest_yuyv.size()));
    if (out == nullptr) {
        return nullptr;
    }
    env->SetByteArrayRegion(
        out,
        0,
        static_cast<jsize>(g_latest_yuyv.size()),
        reinterpret_cast<const jbyte *>(g_latest_yuyv.data()));
    return out;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeGetLatestFrameWidth(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    return static_cast<jint>(g_latest_width);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeGetLatestFrameHeight(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    return static_cast<jint>(g_latest_height);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeGetLatestFrameFormat(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    return static_cast<jint>(g_latest_format);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM * vm, void *) {
    g_vm = vm;
    JNIEnv * env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }
    jclass local_class = env->FindClass("com/example/insta360link_android_test/MainActivity");
    if (local_class == nullptr) {
        return JNI_ERR;
    }
    g_main_activity_class = static_cast<jclass>(env->NewGlobalRef(local_class));
    env->DeleteLocalRef(local_class);
    g_dispatch_event = env->GetStaticMethodID(
        g_main_activity_class,
        "dispatchNativeEvent",
        "(Ljava/lang/String;Ljava/lang/String;)V");
    if (g_dispatch_event == nullptr) {
        return JNI_ERR;
    }
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *, void *) {
    if (g_vm == nullptr) {
        return;
    }
    JNIEnv * env = nullptr;
    if (g_vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return;
    }
    if (g_main_activity_class != nullptr) {
        env->DeleteGlobalRef(g_main_activity_class);
        g_main_activity_class = nullptr;
    }
}
