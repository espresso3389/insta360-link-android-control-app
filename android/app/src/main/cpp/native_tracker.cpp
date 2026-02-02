#include <jni.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>

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

void worker_loop() {
    emit_state("running", "Native tracker started (mock telemetry).");
    int frame = 0;
    while (g_running.load()) {
        const double t = frame * 0.07;
        const double cx = 0.45 + 0.15 * std::sin(t);
        const double cy = 0.35 + 0.10 * std::cos(t * 0.8);
        const double w = 0.20;
        const double h = 0.25;
        const double score = 0.92;

        std::ostringstream face;
        face.setf(std::ios::fixed);
        face.precision(4);
        face << "{\"x\":" << cx << ",\"y\":" << cy << ",\"w\":" << w << ",\"h\":" << h
             << ",\"score\":" << score << "}";
        send_event("face", face.str());

        float kp_x;
        float kd_x;
        float kp_y;
        float kd_y;
        {
            std::lock_guard<std::mutex> lock(g_state_mutex);
            kp_x = g_kp_x;
            kd_x = g_kd_x;
            kp_y = g_kp_y;
            kd_y = g_kd_y;
        }

        const double err_x = cx - 0.5;
        const double err_y = cy - 0.5;
        const double pan = -(kp_x * err_x + kd_x * err_x * 0.5f);
        const double tilt = -(kp_y * err_y + kd_y * err_y * 0.5f);
        const double fps = 15.0;
        const double latency_ms = 18.0 + 4.0 * std::abs(std::sin(t));

        std::ostringstream telemetry;
        telemetry.setf(std::ios::fixed);
        telemetry.precision(3);
        telemetry << "{\"fps\":" << fps << ",\"latencyMs\":" << latency_ms << ",\"pan\":" << pan
                  << ",\"tilt\":" << tilt << "}";
        send_event("telemetry", telemetry.str());

        std::this_thread::sleep_for(std::chrono::milliseconds(67));
        ++frame;
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

    std::ostringstream msg;
    msg << "{\"status\":\"connected\",\"message\":\"USB attached (fd=" << g_usb_fd << ", vid=0x"
        << std::hex << g_usb_vid << ", pid=0x" << g_usb_pid << ").\"}";
    send_event("state", msg.str());
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_insta360link_1android_1test_MainActivity_nativeDetachUsb(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_usb_fd = -1;
    g_usb_vid = 0;
    g_usb_pid = 0;
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
    }
    emit_state("idle", "Native tracker disposed.");
    return JNI_TRUE;
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
