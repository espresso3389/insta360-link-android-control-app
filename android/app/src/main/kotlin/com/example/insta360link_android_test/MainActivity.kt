package com.example.insta360link_android_test

import android.Manifest
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.ImageFormat
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbRequest
import android.media.Image
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.Surface
import android.media.ImageReader
import android.graphics.Rect
import android.graphics.YuvImage
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val tag = "InstaLinkTracker"
    private val methodChannelName = "insta_link_tracker/methods"
    private val eventChannelName = "insta_link_tracker/events"
    private val usbPermissionAction = "com.example.insta360link_android_test.USB_PERMISSION"
    private val cameraPermissionRequestCode = 22001
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var usbManager: UsbManager
    private var eventSink: EventChannel.EventSink? = null
    private var usbDevice: UsbDevice? = null
    private var usbConnection: UsbDeviceConnection? = null
    private val claimedInterfaces = mutableListOf<UsbInterface>()
    private var isCameraActive = false
    private var activeStreamEndpoint: UsbEndpoint? = null
    private val streamReaderRunning = AtomicBoolean(false)
    private var streamReaderThread: Thread? = null
    private val panDeadzone = 0.08f
    private val tiltDeadzone = 0.08f
    private var currentPanAbs = 0
    private var currentTiltAbs = 0
    private var currentZoomLevel = 0f
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var cameraFramesSinceReport = 0L
    private var cameraLastReportMs = 0L
    private var previewWarmupUntilMs = 0L
    private var autoReconnectEnabled = true
    private var lastTargetVid = -1
    private var lastTargetPid = -1
    private var trackingEnabled = false
    private var nativeTrackingActive = false
    private var yoloTracker: YoloV8FaceTracker? = null
    private var yoloInitFailureNotified = false
    private var lastInferenceMs = 0L
    private var lastTelemetryMs = 0L
    private var lastAutoGimbalMs = 0L
    private var lastNoFaceNoticeMs = 0L
    private var lastErrX = 0f
    private var lastErrY = 0f
    private var lastFaceCx = 0.5f
    private var lastFaceCy = 0.5f
    private var lastFaceW = 0.0f
    private var lastFaceH = 0.0f
    private var lastFaceMs = 0L
    private var lastFaceMotionMs = 0L
    private var patrolMode = false
    private var patrolDirection = 1f
    private var lastPatrolCmdMs = 0L
    private var lastPatrolNoticeMs = 0L
    private var lastPreviewLogMs = 0L
    private var lastPreviewBoundsLogMs = 0L
    private var previewRearmAttempted = false
    private var previewGreenSinceMs = 0L
    private var pidKpX = -1.20f
    private var pidKiX = 0f
    private var pidKdX = -0.12f
    private var pidKpY = 1.00f
    private var pidKiY = 0f
    private var pidKdY = 0.10f
    private var errIntX = 0f
    private var errIntY = 0f
    private var filteredPan = 0f
    private var filteredTilt = 0f
    private val yoloPollIntervalMs = 180L
    private val yoloPollRunnable =
        object : Runnable {
            override fun run() {
                if (!trackingEnabled) {
                    return
                }
                val now = System.currentTimeMillis()
                processNativeYuyvFrameForTracking(now)
                mainHandler.postDelayed(this, yoloPollIntervalMs)
            }
        }

    private external fun nativeInit(): Boolean
    private external fun nativeAttachUsbFd(fd: Int, vid: Int, pid: Int): Boolean
    private external fun nativeActivateCamera(): Boolean
    private external fun nativeDetachUsb(): Boolean
    private external fun nativeStartTracking(): Boolean
    private external fun nativeStopTracking(): Boolean
    private external fun nativeSetPid(
        kpX: Float,
        kiX: Float,
        kdX: Float,
        kpY: Float,
        kiY: Float,
        kdY: Float,
    ): Boolean

    private external fun nativeSetTargetPolicy(mode: String): Boolean
    private external fun nativeManualControl(pan: Float, tilt: Float, durationMs: Int): Boolean
    private external fun nativeDispose(): Boolean
    private external fun nativeGetLatestYuyvFrame(): ByteArray?
    private external fun nativeGetLatestFrameWidth(): Int
    private external fun nativeGetLatestFrameHeight(): Int
    private external fun nativeGetLatestFrameFormat(): Int

    private val usbPermissionReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != usbPermissionAction) {
                    return
                }
                @Suppress("DEPRECATION")
                val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                if (granted) {
                    dispatchNativeEvent(
                        "state",
                        """{"status":"ready","message":"USB permission granted for ${device?.productName ?: "device"}."}""",
                    )
                } else {
                    dispatchNativeEvent("state", """{"status":"error","message":"USB permission denied."}""")
                }
            }
        }

    private val usbAttachReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                @Suppress("DEPRECATION")
                val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE) ?: return
                if (action == UsbManager.ACTION_USB_DEVICE_DETACHED) {
                    val cur = usbDevice
                    if (cur != null && cur.vendorId == device.vendorId && cur.productId == device.productId) {
                        dispatchNativeEvent(
                            "state",
                            """{"status":"ready","message":"USB camera detached. Waiting for reconnect..."}""",
                        )
                        stopAndDetachUsb()
                    }
                    return
                }
                if (action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
                    if (!autoReconnectEnabled || !isLikelyUvcDevice(device)) {
                        return
                    }
                    val targetMatch =
                        (lastTargetVid < 0 || lastTargetPid < 0) ||
                            (device.vendorId == lastTargetVid && device.productId == lastTargetPid)
                    if (!targetMatch) {
                        return
                    }
                    dispatchNativeEvent(
                        "state",
                        """{"status":"ready","message":"UVC camera attached. Auto-reconnecting..."}""",
                    )
                    mainHandler.postDelayed({
                        connectUsbDevice(device.vendorId, device.productId)
                    }, 400)
                }
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
        eventChannel.setStreamHandler(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                usbPermissionReceiver,
                IntentFilter(usbPermissionAction),
                Context.RECEIVER_NOT_EXPORTED,
            )
            registerReceiver(
                usbAttachReceiver,
                IntentFilter().apply {
                    addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                    addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
                },
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            registerReceiver(usbPermissionReceiver, IntentFilter(usbPermissionAction))
            registerReceiver(
                usbAttachReceiver,
                IntentFilter().apply {
                    addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                    addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
                },
            )
        }
        instance = this
        handleAdbControlIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAdbControlIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopAndDetachUsb()
        nativeDispose()
        unregisterReceiver(usbPermissionReceiver)
        unregisterReceiver(usbAttachReceiver)
        instance = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> result.success(nativeInit())
            "listDevices" -> result.success(listUsbDevices())

            "connectDevice" -> {
                val args = call.arguments as? Map<*, *>
                val vid = (args?.get("vid") as? Number)?.toInt() ?: 0
                val pid = (args?.get("pid") as? Number)?.toInt() ?: 0
                result.success(connectUsbDevice(vid, pid))
            }

            "startTracking" -> {
                result.success(startTrackingPipeline())
            }
            "stopTracking" -> result.success(stopTrackingPipeline())
            "pauseTracking" -> result.success(pauseTrackingPipeline())
            "setPid" -> {
                val args = call.arguments as? Map<*, *>
                val kpX = (args?.get("kpX") as? Number)?.toFloat() ?: 0f
                val kiX = (args?.get("kiX") as? Number)?.toFloat() ?: 0f
                val kdX = (args?.get("kdX") as? Number)?.toFloat() ?: 0f
                val kpY = (args?.get("kpY") as? Number)?.toFloat() ?: 0f
                val kiY = (args?.get("kiY") as? Number)?.toFloat() ?: 0f
                val kdY = (args?.get("kdY") as? Number)?.toFloat() ?: 0f
                pidKpX = kpX
                pidKiX = kiX
                pidKdX = kdX
                pidKpY = kpY
                pidKiY = kiY
                pidKdY = kdY
                result.success(nativeSetPid(kpX, kiX, kdX, kpY, kiY, kdY))
            }

            "setTargetPolicy" -> {
                val args = call.arguments as? Map<*, *>
                val mode = (args?.get("mode") as? String) ?: "largest"
                result.success(nativeSetTargetPolicy(mode))
            }

            "manualControl" -> {
                val args = call.arguments as? Map<*, *>
                val pan = (args?.get("pan") as? Number)?.toFloat() ?: 0f
                val tilt = (args?.get("tilt") as? Number)?.toFloat() ?: 0f
                val durationMs = (args?.get("durationMs") as? Number)?.toInt() ?: 300
                if (!isCameraActive && !activateCameraStreamInterface()) {
                    result.success(false)
                    return
                }
                val isCenter = isCenterCommand(pan, tilt)
                if (isCenter) {
                    currentPanAbs = 0
                    currentTiltAbs = 0
                }
                val ok = sendManualGimbalCommand(pan, tilt, durationMs, force = isCenter)
                nativeManualControl(pan, tilt, durationMs)
                result.success(ok)
            }
            "manualZoom" -> {
                val args = call.arguments as? Map<*, *>
                val zoom = (args?.get("zoom") as? Number)?.toFloat() ?: 0f
                val durationMs = (args?.get("durationMs") as? Number)?.toInt() ?: 300
                if (!isCameraActive && !activateCameraStreamInterface()) {
                    result.success(false)
                    return
                }
                result.success(sendManualZoomCommand(zoom, durationMs))
            }

            "activateCamera" -> result.success(activateCameraStreamInterface())
            "activateCamera2" -> result.success(activateCameraWithCamera2())
            "reconnect" -> result.success(reconnectLastDevice())
            "getPreviewJpeg" -> result.success(getPreviewJpegFrame())
            "dumpPreview" -> {
                val ok = dumpPreviewToFile("/sdcard/Download/preview.jpg")
                result.success(ok)
            }
            "recoverPreview" -> {
                result.success(recoverPreviewSequence())
            }

            "dispose" -> {
                stopAndDetachUsb()
                result.success(nativeDispose())
            }

            else -> result.notImplemented()
        }
    }

    private fun getPreviewJpegFrame(ignoreWarmup: Boolean = false): ByteArray? {
        val format = nativeGetLatestFrameFormat()
        val w = nativeGetLatestFrameWidth()
        val h = nativeGetLatestFrameHeight()
        val frame = nativeGetLatestYuyvFrame()
        if (!ignoreWarmup && System.currentTimeMillis() < previewWarmupUntilMs) {
            return null
        }
        if (frame == null || w <= 0 || h <= 0) {
            return null
        }
        val now = System.currentTimeMillis()
        var path = "unknown"
        if (format == 2) {
            if (now - lastPreviewLogMs > 2000) {
                lastPreviewLogMs = now
                Log.i(tag, "preview raw fmt=2 len=${frame.size} head=${hexHead(frame, 12)}")
            }
            val direct = extractJpeg(frame)
            if (direct != null) {
                if (now - lastPreviewBoundsLogMs > 2000) {
                    val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(direct, 0, direct.size, opts)
                    lastPreviewBoundsLogMs = now
                    Log.i(tag, "preview jpeg bounds=${opts.outWidth}x${opts.outHeight} bytes=${direct.size}")
                }
                val decoded = decodeJpegToBytes(direct)
                if (decoded != null) {
                    path = "mjpeg->reencode"
                    if (now - lastPreviewLogMs > 2000) {
                        lastPreviewLogMs = now
                        Log.i(tag, "preview path=$path len=${decoded.size} fmt=$format size=${w}x${h}")
                    }
                    checkGreenAndRecover(decoded)
                    return decoded
                }
                Log.w(tag, "Preview MJPEG decode returned null; trying YUYV fallback")
            }
            Log.w(tag, "Preview MJPEG decode failed len=${frame.size}; trying YUYV fallback")
            val fallback =
                yuyvToJpeg(frame, w, h, uyvy = false) ?: yuyvToJpeg(frame, w, h, uyvy = true)
            if (fallback != null && now - lastPreviewLogMs > 2000) {
                lastPreviewLogMs = now
                path = "mjpeg->yuyv-fallback"
                Log.i(tag, "preview path=$path len=${fallback.size} fmt=$format size=${w}x${h}")
            }
            if (fallback != null) {
                checkGreenAndRecover(fallback)
            }
            return fallback
        }
        if (format == 1) {
            val out = yuyvToJpeg(frame, w, h, uyvy = false) ?: yuyvToJpeg(frame, w, h, uyvy = true)
            if (out != null && now - lastPreviewLogMs > 2000) {
                lastPreviewLogMs = now
                path = "yuyv"
                Log.i(tag, "preview path=$path len=${out.size} fmt=$format size=${w}x${h}")
            }
            if (out != null) {
                checkGreenAndRecover(out)
            }
            return out
        }
        return null
    }

    private fun hexHead(data: ByteArray, count: Int): String {
        val limit = count.coerceAtMost(data.size)
        val sb = StringBuilder()
        for (i in 0 until limit) {
            sb.append(String.format("%02X", data[i]))
            if (i + 1 < limit) sb.append(" ")
        }
        return sb.toString()
    }

    private fun schedulePreviewRearmCheck() {
        if (previewRearmAttempted) {
            return
        }
        previewRearmAttempted = true
        thread(name = "PreviewRearm", isDaemon = true) {
            Thread.sleep(1600)
            val jpeg = getPreviewJpegFrame(ignoreWarmup = true) ?: return@thread
            if (!isLikelyGreenJpeg(jpeg)) {
                return@thread
            }
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Preview looks green. Restarting UVC stream..."}""",
            )
            nativeStopTracking()
            nativeTrackingActive = false
            Thread.sleep(800)
            val ok = nativeStartTracking()
            nativeTrackingActive = ok
            previewWarmupUntilMs = System.currentTimeMillis() + 1200
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"UVC stream restart ${if (ok) "done" else "failed"}."}""",
            )
        }
    }

    private fun isLikelyGreenJpeg(jpeg: ByteArray): Boolean {
        val opts = BitmapFactory.Options().apply { inSampleSize = 16 }
        val bmp = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, opts) ?: return false
        val w = bmp.width
        val h = bmp.height
        if (w <= 0 || h <= 0) return false
        var rSum = 0L
        var gSum = 0L
        var bSum = 0L
        var count = 0L
        val stepX = max(1, w / 16)
        val stepY = max(1, h / 12)
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                val c = bmp.getPixel(x, y)
                rSum += (c shr 16) and 0xFF
                gSum += (c shr 8) and 0xFF
                bSum += c and 0xFF
                count++
                x += stepX
            }
            y += stepY
        }
        if (count == 0L) return false
        val rAvg = rSum / count
        val gAvg = gSum / count
        val bAvg = bSum / count
        return gAvg > 90 && rAvg < 30 && bAvg < 30 && gAvg > (rAvg + bAvg) * 2
    }

    private fun checkGreenAndRecover(jpeg: ByteArray) {
        val now = System.currentTimeMillis()
        if (isLikelyGreenJpeg(jpeg)) {
            if (previewGreenSinceMs == 0L) {
                previewGreenSinceMs = now
            }
            val greenForMs = now - previewGreenSinceMs
            if (greenForMs > 2500 && !previewRearmAttempted) {
                previewRearmAttempted = true
                thread(name = "PreviewAutoRecover", isDaemon = true) {
                    dispatchNativeEvent(
                        "state",
                        """{"status":"ready","message":"Preview still green. Auto-recovering..."}""",
                    )
                    recoverPreviewSequence()
                }
            }
        } else {
            previewGreenSinceMs = 0L
            previewRearmAttempted = false
        }
    }

    private fun recoverPreviewSequence(): Boolean {
        return try {
            nativeStopTracking()
            nativeTrackingActive = false
            Thread.sleep(300)
            nativeInit()
            Thread.sleep(300)
            val device = usbManager.deviceList.values.firstOrNull { isLikelyUvcDevice(it) }
            if (device != null) {
                connectUsbDevice(device.vendorId, device.productId)
            }
            Thread.sleep(400)
            val ok = activateCameraStreamInterface()
            previewWarmupUntilMs = System.currentTimeMillis() + 1500
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Recovery sequence finished (activate=$ok)."}""",
            )
            ok
        } catch (t: Throwable) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Recovery failed: ${t.message ?: "unknown"}"}""",
            )
            false
        }
    }

    private fun dumpPreviewToFile(path: String): Boolean {
        val data = getPreviewJpegFrame(ignoreWarmup = true) ?: return false
        return try {
            val file = java.io.File(path)
            file.outputStream().use { it.write(data) }
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Preview dumped to $path (${data.size} bytes)."}""",
            )
            true
        } catch (t: Throwable) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Dump preview failed: ${t.message ?: "unknown"}"}""",
            )
            false
        }
    }


    private fun extractJpeg(frame: ByteArray): ByteArray? {
        var start = -1
        var end = -1
        var i = 0
        while (i + 1 < frame.size) {
            if (start < 0 && frame[i] == 0xFF.toByte() && frame[i + 1] == 0xD8.toByte()) {
                start = i
                i += 2
                continue
            }
            if (start >= 0 && frame[i] == 0xFF.toByte() && frame[i + 1] == 0xD9.toByte()) {
                end = i + 2
                break
            }
            i++
        }
        if (start >= 0) {
            val sliceEnd = if (end > start) end else frame.size
            return frame.copyOfRange(start, sliceEnd)
        }
        return null
    }

    private fun decodeJpegToBytes(jpeg: ByteArray): ByteArray? {
        val bitmap =
            BitmapFactory.decodeByteArray(
                jpeg,
                0,
                jpeg.size,
                BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 },
            ) ?: return null
        val out = ByteArrayOutputStream()
        val ok = bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
        return if (ok) out.toByteArray() else null
    }

    private fun yuyvToJpeg(
        yuyv: ByteArray,
        width: Int,
        height: Int,
        uyvy: Boolean,
    ): ByteArray? {
        val frameSize = width * height
        val nv21 = ByteArray(frameSize + frameSize / 2)
        var yIndex = 0
        var uvIndex = frameSize
        var i = 0
        for (row in 0 until height) {
            val rowIsEven = (row and 1) == 0
            var col = 0
            while (col < width && i + 3 < yuyv.size) {
                val y0: Int
                val y1: Int
                val u: Int
                val v: Int
                if (uyvy) {
                    u = yuyv[i].toInt() and 0xFF
                    y0 = yuyv[i + 1].toInt() and 0xFF
                    v = yuyv[i + 2].toInt() and 0xFF
                    y1 = yuyv[i + 3].toInt() and 0xFF
                } else {
                    y0 = yuyv[i].toInt() and 0xFF
                    u = yuyv[i + 1].toInt() and 0xFF
                    y1 = yuyv[i + 2].toInt() and 0xFF
                    v = yuyv[i + 3].toInt() and 0xFF
                }
                nv21[yIndex++] = y0.toByte()
                if (col + 1 < width) {
                    nv21[yIndex++] = y1.toByte()
                }
                if (rowIsEven && uvIndex + 1 < nv21.size) {
                    nv21[uvIndex++] = v.toByte()
                    nv21[uvIndex++] = u.toByte()
                }
                i += 4
                col += 2
            }
        }
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val out = ByteArrayOutputStream()
        val ok = yuvImage.compressToJpeg(Rect(0, 0, width, height), 70, out)
        return if (ok) out.toByteArray() else null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun listUsbDevices(): List<Map<String, Any>> {
        val devices = mutableListOf<Map<String, Any>>()
        for (device in usbManager.deviceList.values) {
            val isUvc = isLikelyUvcDevice(device)
            devices.add(
                mapOf(
                    "name" to (device.productName ?: device.deviceName),
                    "vid" to device.vendorId,
                    "pid" to device.productId,
                    "deviceClass" to device.deviceClass,
                    "interfaceCount" to device.interfaceCount,
                    "isUvc" to isUvc,
                    "hasPermission" to usbManager.hasPermission(device),
                ),
            )
        }
        return devices
    }

    private fun connectUsbDevice(vid: Int, pid: Int): Boolean {
        lastTargetVid = vid
        lastTargetPid = pid
        if (!ensureCameraPermission()) {
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Camera permission required. Allow permission, then run connect again."}""",
            )
            return false
        }

        val device =
            usbManager.deviceList.values.firstOrNull {
                it.vendorId == vid && it.productId == pid
            }
                ?: run {
                    Log.w(tag, "connectUsbDevice: device not found vid=$vid pid=$pid")
                    dispatchNativeEvent(
                        "state",
                        """{"status":"error","message":"Device not found vid=$vid pid=$pid"}""",
                    )
                    return false
                }

        if (!ensureUsbPermission(device)) {
            Log.i(tag, "connectUsbDevice: waiting for permission vid=$vid pid=$pid")
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"USB permission pending. Allow prompt, then run connect again."}""",
            )
            return false
        }

        stopAndDetachUsb()
        val connection = usbManager.openDevice(device) ?: run {
            Log.e(tag, "connectUsbDevice: openDevice failed vid=$vid pid=$pid")
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Failed to open USB device."}""",
            )
            return false
        }

        val ok = nativeAttachUsbFd(connection.fileDescriptor, vid, pid)
        if (!ok) {
            Log.e(tag, "connectUsbDevice: nativeAttachUsbFd failed vid=$vid pid=$pid")
            connection.close()
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Native attach failed for USB device."}""",
            )
            return false
        }

        claimVideoInterfaces(connection, device)
        usbDevice = device
        usbConnection = connection
        isCameraActive = false
        currentPanAbs = 0
        currentTiltAbs = 0
        Log.i(tag, "connectUsbDevice: connected vid=$vid pid=$pid fd=${connection.fileDescriptor}")
        dispatchNativeEvent("state", """{"status":"connected","message":"USB device connected."}""")
        return true
    }

    private fun reconnectLastDevice(): Boolean {
        if (lastTargetVid < 0 || lastTargetPid < 0) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No previous target device to reconnect."}""",
            )
            return false
        }
        dispatchNativeEvent(
            "state",
            """{"status":"ready","message":"Reconnecting to $lastTargetVid:$lastTargetPid..."}""",
        )
        return connectUsbDevice(lastTargetVid, lastTargetPid)
    }

    private fun ensureUsbPermission(device: UsbDevice): Boolean {
        if (usbManager.hasPermission(device)) {
            return true
        }

        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        val permissionIntent = Intent(usbPermissionAction).setPackage(packageName)
        val intent = PendingIntent.getBroadcast(this, device.deviceId, permissionIntent, flags)
        usbManager.requestPermission(device, intent)
        Log.i(tag, "ensureUsbPermission: requested permission for vid=${device.vendorId} pid=${device.productId}")
        dispatchNativeEvent(
            "state",
            """{"status":"ready","message":"Requested USB permission. Tap Connect again after allowing it."}""",
        )
        return false
    }

    private fun ensureCameraPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val granted =
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) {
            return true
        }
        requestPermissions(arrayOf(Manifest.permission.CAMERA), cameraPermissionRequestCode)
        Log.i(tag, "ensureCameraPermission: requested CAMERA runtime permission")
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != cameraPermissionRequestCode) {
            return
        }
        val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) {
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Camera permission granted. Run connect again."}""",
            )
        } else {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Camera permission denied."}""",
            )
        }
    }

    private fun isLikelyUvcDevice(device: UsbDevice): Boolean {
        if (device.deviceClass == UsbConstants.USB_CLASS_VIDEO) {
            return true
        }
        for (i in 0 until device.interfaceCount) {
            if (device.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_VIDEO) {
                return true
            }
        }
        return false
    }

    private fun stopAndDetachUsb() {
        trackingEnabled = false
        mainHandler.removeCallbacks(yoloPollRunnable)
        stopCamera2Pipeline()
        stopStreamReader()
        nativeStopTracking()
        nativeDetachUsb()
        releaseClaimedInterfaces()
        usbConnection?.close()
        usbConnection = null
        usbDevice = null
        activeStreamEndpoint = null
        isCameraActive = false
        currentPanAbs = 0
        currentTiltAbs = 0
        lastFaceW = 0.0f
        lastFaceH = 0.0f
        lastFaceMotionMs = 0L
        patrolMode = false
        patrolDirection = 1f
        lastPatrolCmdMs = 0L
        lastPatrolNoticeMs = 0L
        runCatching { yoloTracker?.close() }
        yoloTracker = null
        yoloInitFailureNotified = false
    }

    private fun handleAdbControlIntent(incoming: Intent?) {
        val command = incoming?.getStringExtra("cmd") ?: return
        when (command) {
            "init" -> nativeInit()
            "list" -> {
                val list = listUsbDevices()
                val payload = JSONObject().put("status", "ready").put("devices", list).toString()
                dispatchNativeEvent("state", payload)
            }

            "connect" -> {
                val vid = incoming.getIntExtra("vid", 0)
                val pid = incoming.getIntExtra("pid", 0)
                connectUsbDevice(vid, pid)
            }

            "start" -> {
                startTrackingPipeline()
            }
            "stop" -> stopTrackingPipeline()
            "setpid" -> {
                val kpX = incoming.getFloatExtra("kpX", pidKpX)
                val kiX = incoming.getFloatExtra("kiX", pidKiX)
                val kdX = incoming.getFloatExtra("kdX", pidKdX)
                val kpY = incoming.getFloatExtra("kpY", pidKpY)
                val kiY = incoming.getFloatExtra("kiY", pidKiY)
                val kdY = incoming.getFloatExtra("kdY", pidKdY)
                pidKpX = kpX
                pidKiX = kiX
                pidKdX = kdX
                pidKpY = kpY
                pidKiY = kiY
                pidKdY = kdY
                nativeSetPid(kpX, kiX, kdX, kpY, kiY, kdY)
                dispatchNativeEvent(
                    "state",
                    """{"status":"ready","message":"PID updated kpX=$kpX kiX=$kiX kdX=$kdX kpY=$kpY kiY=$kiY kdY=$kdY"}""",
                )
            }
            "detach" -> stopAndDetachUsb()
            "policy" -> {
                val mode = incoming.getStringExtra("mode") ?: "largest"
                nativeSetTargetPolicy(mode)
            }

            "manual" -> {
                val pan = incoming.getFloatExtra("pan", 0f)
                val tilt = incoming.getFloatExtra("tilt", 0f)
                val durationMs = incoming.getIntExtra("durationMs", 300)
                if (!isCameraActive && !activateCameraStreamInterface()) {
                    return
                }
                val isCenter = isCenterCommand(pan, tilt)
                if (isCenter) {
                    currentPanAbs = 0
                    currentTiltAbs = 0
                }
                sendManualGimbalCommand(pan, tilt, durationMs, force = isCenter)
                nativeManualControl(pan, tilt, durationMs)
            }
            "zoom" -> {
                val zoom = incoming.getFloatExtra("zoom", 0f)
                val durationMs = incoming.getIntExtra("durationMs", 300)
                if (!isCameraActive && !activateCameraStreamInterface()) {
                    return
                }
                sendManualZoomCommand(zoom, durationMs)
            }

            "activate" -> activateCameraStreamInterface()
            "activate2" -> activateCameraWithCamera2()
            "probeptz" -> runPtzProbeSweep()
            "dumpxu" -> dumpExtensionUnits()
            "probexu" -> runXuProbeSweep()
            "replaylinux" -> replayLinuxBaselinePtz()
            "dumpPreview" -> dumpPreviewToFile("/sdcard/Download/preview.jpg")
        }
    }

    private fun replayLinuxBaselinePtz() {
        val connection = usbConnection
        if (connection == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No USB connection. Connect first, then replaylinux."}""",
            )
            return
        }
        val requestType = 0x21
        val request = 0x01
        val value = 0x0D00
        val index = 0x0100
        val timeoutMs = 1000
        val packets =
            listOf(
                byteArrayOf(0x90.toByte(), 0x5f, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00), // pan +90000
                byteArrayOf(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00), // center
                byteArrayOf(0x00, 0x00, 0x00, 0x00, 0x30, 0x0b, 0x01, 0x00), // tilt +68400
                byteArrayOf(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00), // center
            )
        thread(name = "ReplayLinuxPTZ", isDaemon = true) {
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Replaying Linux baseline PTZ sequence..."}""",
            )
            for (packet in packets) {
                val sent =
                    connection.controlTransfer(
                        requestType,
                        request,
                        value,
                        index,
                        packet,
                        packet.size,
                        timeoutMs,
                    )
                Log.i(tag, "replaylinux: sent=$sent packet=${packet.joinToString("") { "%02x".format(it) }}")
                Thread.sleep(250)
            }
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Linux baseline PTZ replay done."}""",
            )
        }
    }

    private data class XuUnit(val unitId: Int, val bmControls: ByteArray, val guid: String)

    private fun parseExtensionUnitsFromRaw(raw: ByteArray): List<XuUnit> {
        val out = mutableListOf<XuUnit>()
        var i = 0
        while (i + 2 < raw.size) {
            val len = raw[i].toInt() and 0xFF
            if (len <= 0 || i + len > raw.size) {
                break
            }
            val dtype = raw[i + 1].toInt() and 0xFF
            val subtype = if (len >= 3) (raw[i + 2].toInt() and 0xFF) else -1
            if (dtype == 0x24 && subtype == 0x06 && len >= 24) {
                val unitId = raw[i + 3].toInt() and 0xFF
                val guidBytes = raw.copyOfRange(i + 4, i + 20)
                val guid = guidBytes.joinToString("") { "%02X".format(it.toInt() and 0xFF) }
                val numPins = raw[i + 21].toInt() and 0xFF
                val ctrlSizeIndex = i + 22 + numPins
                val ctrlSize = if (ctrlSizeIndex < i + len) (raw[ctrlSizeIndex].toInt() and 0xFF) else 0
                val ctrlStart = ctrlSizeIndex + 1
                val ctrlEnd = (ctrlStart + ctrlSize).coerceAtMost(i + len)
                val bm = if (ctrlStart < ctrlEnd) raw.copyOfRange(ctrlStart, ctrlEnd) else ByteArray(0)
                out.add(XuUnit(unitId, bm, guid))
            }
            i += len
        }
        return out
    }

    private fun dumpExtensionUnits() {
        val connection = usbConnection
        if (connection == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No USB connection. Connect first, then dumpxu."}""",
            )
            return
        }
        val raw = connection.rawDescriptors
        if (raw == null || raw.isEmpty()) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No raw USB descriptors available."}""",
            )
            return
        }
        val units = parseExtensionUnitsFromRaw(raw)
        if (units.isEmpty()) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No XU descriptors found in raw descriptors."}""",
            )
            return
        }
        for (u in units) {
            val bmHex = u.bmControls.joinToString("") { "%02X".format(it.toInt() and 0xFF) }
                Log.i(
                    tag,
                    "XU unit=${u.unitId} guid=${u.guid} ctrlSize=${u.bmControls.size} bmControls=$bmHex",
                )
                dispatchNativeEvent(
                    "state",
                    """{"status":"ready","message":"XU unit=${u.unitId} guid=${u.guid} ctrlSize=${u.bmControls.size} bm=$bmHex"}""",
                )
        }
        dispatchNativeEvent(
            "state",
            """{"status":"ready","message":"dumpxu done. Found ${units.size} extension unit(s)."}""",
        )
    }

    private fun runXuProbeSweep() {
        val connection = usbConnection
        val device = usbDevice
        if (connection == null || device == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No USB connection. Connect first, then probexu."}""",
            )
            return
        }
        val vcInterface = findVideoControlInterfaceNumber(device)
        if (vcInterface < 0) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No VC interface found for XU probe."}""",
            )
            return
        }
        val raw = connection.rawDescriptors ?: ByteArray(0)
        val units = parseExtensionUnitsFromRaw(raw)
        if (units.isEmpty()) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No XU units found. Run dumpxu first."}""",
            )
            return
        }
        dispatchNativeEvent(
            "state",
            """{"status":"ready","message":"XU probe started (~15s). Watch for left/right yaw."}""",
        )
        thread(name = "XuProbe", isDaemon = true) {
            val reqTypeIn = 0xA1
            val reqTypeOut = 0x21
            val getLen = 0x85
            val getInfo = 0x86
            val setCur = 0x01
            for (u in units) {
                val selectors =
                    (1..32).filter { sel ->
                        val byteIdx = (sel - 1) / 8
                        val bitIdx = (sel - 1) % 8
                        byteIdx < u.bmControls.size && ((u.bmControls[byteIdx].toInt() ushr bitIdx) and 0x1) == 1
                    }
                dispatchNativeEvent(
                    "state",
                    """{"status":"ready","message":"XU unit=${u.unitId} selectors=${selectors.joinToString(",")}"}""",
                )
                for (sel in selectors.take(8)) {
                    val wIndex = (u.unitId shl 8) or (vcInterface and 0xFF)
                    val lenBuf = ByteArray(2)
                    val infoBuf = ByteArray(1)
                    val lenRc = connection.controlTransfer(reqTypeIn, getLen, sel shl 8, wIndex, lenBuf, lenBuf.size, 180)
                    val infoRc = connection.controlTransfer(reqTypeIn, getInfo, sel shl 8, wIndex, infoBuf, infoBuf.size, 180)
                    val ctrlLen =
                        if (lenRc >= 2) {
                            (lenBuf[0].toInt() and 0xFF) or ((lenBuf[1].toInt() and 0xFF) shl 8)
                        } else {
                            8
                        }.coerceIn(1, 16)
                    val info = if (infoRc >= 1) (infoBuf[0].toInt() and 0xFF) else -1
                    Log.i(tag, "XU PROBE unit=${u.unitId} sel=$sel lenRc=$lenRc len=$ctrlLen infoRc=$infoRc info=$info")
                    if (ctrlLen <= 0) {
                        continue
                    }
                    val plus = ByteArray(ctrlLen)
                    val minus = ByteArray(ctrlLen)
                    if (ctrlLen >= 4) {
                        ByteBuffer.wrap(plus).order(ByteOrder.LITTLE_ENDIAN).putInt(30000)
                        ByteBuffer.wrap(minus).order(ByteOrder.LITTLE_ENDIAN).putInt(-30000)
                    } else {
                        plus[0] = 40
                        minus[0] = (-40).toByte()
                    }
                    val rcPlus =
                        connection.controlTransfer(reqTypeOut, setCur, sel shl 8, wIndex, plus, plus.size, 220)
                    Thread.sleep(220)
                    val rcMinus =
                        connection.controlTransfer(reqTypeOut, setCur, sel shl 8, wIndex, minus, minus.size, 220)
                    Thread.sleep(220)
                    Log.i(
                        tag,
                        "XU PROBE SET unit=${u.unitId} sel=$sel len=$ctrlLen rcPlus=$rcPlus rcMinus=$rcMinus",
                    )
                }
            }
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"XU probe finished. Tell me which step caused yaw."}""",
            )
        }
    }

    private fun runPtzProbeSweep() {
        val connection = usbConnection
        val device = usbDevice
        if (connection == null || device == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No USB connection. Connect first, then probeptz."}""",
            )
            return
        }
        val vcInterface = findVideoControlInterfaceNumber(device)
        if (vcInterface < 0) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No VC interface found for PTZ probe."}""",
            )
            return
        }
        val entities = findPtzEntityCandidates(connection).ifEmpty { listOf(1, 2, 3, 4, 5, 6, 9, 10, 11) }
        dispatchNativeEvent(
            "state",
            """{"status":"ready","message":"PTZ probe started. Watch camera movement for ~12s."}""",
        )
        thread(name = "PtzProbe", isDaemon = true) {
            val reqTypeOut = 0x21
            val setCur = 0x01
            val absSelector = 0x0D
            val relSelector = 0x0E

            fun send(
                label: String,
                selector: Int,
                wIndex: Int,
                payload: ByteArray,
                timeout: Int = 250,
            ): Int {
                val rc =
                    connection.controlTransfer(
                        reqTypeOut,
                        setCur,
                        selector shl 8,
                        wIndex,
                        payload,
                        payload.size,
                        timeout,
                    )
                Log.i(
                    tag,
                    "PTZ PROBE $label selector=0x${selector.toString(16)} wIndex=$wIndex size=${payload.size} rc=$rc payload=${payload.joinToString(",") { (it.toInt() and 0xFF).toString() }}",
                )
                return rc
            }

            for (entityId in entities) {
                val wIndexA = (entityId shl 8) or (vcInterface and 0xFF) // current mapping
                val wIndexB = (vcInterface shl 8) or (entityId and 0xFF) // swapped mapping
                dispatchNativeEvent(
                    "state",
                    """{"status":"ready","message":"PTZ probe entity=$entityId"}""",
                )

                // Absolute candidate, V4L2-like units (small/safe).
                val absPlus =
                    ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putInt(70000).putInt(0).array()
                val absMinus =
                    ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putInt(-70000).putInt(0).array()
                send("absA+", absSelector, wIndexA, absPlus, 350)
                Thread.sleep(260)
                send("absA-", absSelector, wIndexA, absMinus, 350)
                Thread.sleep(260)
                send("absB+", absSelector, wIndexB, absPlus, 350)
                Thread.sleep(260)
                send("absB-", absSelector, wIndexB, absMinus, 350)
                Thread.sleep(260)

                // Relative candidates: standard-like and swapped-axis variants.
                val relAPlus = byteArrayOf(1, 5, 0, 0)   // pan +, tilt 0
                val relAMinus = byteArrayOf((-1).toByte(), 5, 0, 0) // pan -, tilt 0
                val relBPlus = byteArrayOf(0, 0, 1, 5)   // tilt + (or maybe pan on this camera)
                val relBMinus = byteArrayOf(0, 0, (-1).toByte(), 5)
                send("relA+", relSelector, wIndexA, relAPlus, 350)
                Thread.sleep(240)
                send("relA-", relSelector, wIndexA, relAMinus, 350)
                Thread.sleep(240)
                send("relB+", relSelector, wIndexA, relBPlus, 350)
                Thread.sleep(240)
                send("relB-", relSelector, wIndexA, relBMinus, 350)
                Thread.sleep(240)
            }
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"PTZ probe finished. Share what motion you observed."}""",
            )
        }
    }

    private fun activateCameraStreamInterface(): Boolean {
        val ok = nativeActivateCamera()
        isCameraActive = ok
        return ok
    }

    private fun startTrackingPipeline(): Boolean {
        Thread.sleep(250)
        if (!nativeTrackingActive) {
            val nativeTrackerOk = nativeStartTracking()
            if (!nativeTrackerOk) {
                dispatchNativeEvent(
                    "state",
                    """{"status":"error","message":"Native tracking worker failed to start."}""",
                )
                return false
            }
            nativeTrackingActive = true
            isCameraActive = true
        }
        if (ensureYoloTracker() == null) {
            trackingEnabled = false
            return false
        }
        trackingEnabled = true
        lastInferenceMs = 0L
        lastTelemetryMs = 0L
        lastAutoGimbalMs = 0L
        lastNoFaceNoticeMs = 0L
        lastErrX = 0f
        lastErrY = 0f
        lastFaceCx = 0.5f
        lastFaceCy = 0.5f
        lastFaceW = 0.0f
        lastFaceH = 0.0f
        lastFaceMs = 0L
        lastFaceMotionMs = 0L
        patrolMode = false
        patrolDirection = 1f
        lastPatrolCmdMs = 0L
        lastPatrolNoticeMs = 0L
        errIntX = 0f
        errIntY = 0f
        filteredPan = 0f
        filteredTilt = 0f
        mainHandler.removeCallbacks(yoloPollRunnable)
        mainHandler.post(yoloPollRunnable)
        previewWarmupUntilMs = System.currentTimeMillis() + 1500
        previewRearmAttempted = false
        schedulePreviewRearmCheck()

        val msg =
            "Tracking started (libuvc YUYV + YOLOv8n-face + gimbal)."
        dispatchNativeEvent("state", """{"status":"running","message":"$msg"}""")
        return true
    }

    private fun stopTrackingPipeline(): Boolean {
        trackingEnabled = false
        mainHandler.removeCallbacks(yoloPollRunnable)
        errIntX = 0f
        errIntY = 0f
        filteredPan = 0f
        filteredTilt = 0f
        lastFaceMs = 0L
        lastFaceW = 0.0f
        lastFaceH = 0.0f
        lastFaceMotionMs = 0L
        patrolMode = false
        patrolDirection = 1f
        lastPatrolCmdMs = 0L
        lastPatrolNoticeMs = 0L
        nativeStopTracking()
        nativeTrackingActive = false
        previewRearmAttempted = false
        dispatchNativeEvent("state", """{"status":"connected","message":"Tracking stopped."}""")
        return true
    }

    private fun pauseTrackingPipeline(): Boolean {
        trackingEnabled = false
        mainHandler.removeCallbacks(yoloPollRunnable)
        errIntX = 0f
        errIntY = 0f
        filteredPan = 0f
        filteredTilt = 0f
        lastFaceMs = 0L
        lastFaceW = 0.0f
        lastFaceH = 0.0f
        lastFaceMotionMs = 0L
        patrolMode = false
        patrolDirection = 1f
        lastPatrolCmdMs = 0L
        lastPatrolNoticeMs = 0L
        dispatchNativeEvent("state", """{"status":"connected","message":"Tracking paused (manual mode)."}""")
        return true
    }

    private fun ensureYoloTracker(): YoloV8FaceTracker? {
        val existing = yoloTracker
        if (existing != null) {
            return existing
        }
        return try {
            val tracker =
                YoloV8FaceTracker.create(
                    assets,
                    modelAssetCandidates =
                        listOf(
                            "models/yolov8n-face.tflite",
                            "models/yolov8n_face.tflite",
                            "yolov8n-face.tflite",
                        ),
                    modelFileCandidates =
                        listOf(
                            "/sdcard/Download/yolov8n-face.tflite",
                            "/sdcard/Download/yolov8n_face.tflite",
                        ),
                    inputSize = 320,
                    threads = 4,
                )
            yoloTracker = tracker
            yoloInitFailureNotified = false
            dispatchNativeEvent("state", """{"status":"ready","message":"YOLOv8n-face TFLite model loaded."}""")
            tracker
        } catch (t: Throwable) {
            if (!yoloInitFailureNotified) {
                yoloInitFailureNotified = true
                val msg =
                    (t.message ?: "unknown").replace("\"", "'")
                dispatchNativeEvent(
                    "state",
                    """{"status":"error","message":"Failed to load YOLOv8n-face model. Put yolov8n-face.tflite in android/app/src/main/assets/models/ or /sdcard/Download/. detail=$msg"}""",
                )
            }
            null
        }
    }

    private fun processNativeYuyvFrameForTracking(nowMs: Long) {
        if (!trackingEnabled) {
            return
        }
        if (nowMs - lastInferenceMs < 120) {
            return
        }
        lastInferenceMs = nowMs

        val detector = ensureYoloTracker() ?: return
        val w = nativeGetLatestFrameWidth()
        val h = nativeGetLatestFrameHeight()
        val format = nativeGetLatestFrameFormat()
        val frame = nativeGetLatestYuyvFrame()
        if (frame == null || w <= 0 || h <= 0) {
            return
        }
        val t0 = System.nanoTime()
        var detection =
            try {
                when (format) {
                    1 -> detector.detectLargestYuyv(frame, w, h)
                    2 -> detector.detectLargestMjpeg(frame)
                    else -> null
                }
            } catch (t: Throwable) {
                Log.e(tag, "YOLO inference failed", t)
                dispatchNativeEvent(
                    "state",
                    """{"status":"error","message":"YOLO inference failed: ${t.message ?: "unknown"}"}""",
                )
                null
            }
        val latencyMs = (System.nanoTime() - t0) / 1_000_000.0
        var hasDetection = detection != null
        var faceCx = lastFaceCx
        var faceCy = lastFaceCy
        if (hasDetection) {
            val det = detection!!
            faceCx = det.cx
            faceCy = det.cy
            val area = (det.w * det.h).coerceAtLeast(0f)
            val minFaceArea = 0.02f
            if (area < minFaceArea) {
                detection = null
                hasDetection = false
            } else {
                val motionScore =
                    kotlin.math.abs(faceCx - lastFaceCx) +
                        kotlin.math.abs(faceCy - lastFaceCy) +
                        kotlin.math.abs(det.w - lastFaceW) +
                        kotlin.math.abs(det.h - lastFaceH)
                if (motionScore >= 0.006f || lastFaceMotionMs == 0L) {
                    lastFaceMotionMs = nowMs
                }
                val staticIgnoreArea = 0.08f
                if (area < staticIgnoreArea && nowMs - lastFaceMotionMs > 1800) {
                    detection = null
                    hasDetection = false
                }
            }
        }

        if (hasDetection) {
            val det = detection!!
            faceCx = det.cx
            faceCy = det.cy
            lastFaceCx = faceCx
            lastFaceCy = faceCy
            lastFaceW = det.w
            lastFaceH = det.h
            lastFaceMs = nowMs
            if (patrolMode) {
                patrolMode = false
                lastPatrolCmdMs = 0L
                dispatchNativeEvent(
                    "state",
                    """{"status":"running","message":"Face re-acquired. Returning to automatic tracking."}""",
                )
            }
        } else if (nowMs - lastFaceMs <= 900) {
            // Keep short-term continuity when one or two detections drop.
            faceCx = (lastFaceCx * 0.995f + 0.5f * 0.005f)
            faceCy = (lastFaceCy * 0.995f + 0.5f * 0.005f)
            lastFaceCx = faceCx
            lastFaceCy = faceCy
        } else {
            val noFaceMs = nowMs - lastFaceMs
            val patrolStartDelayMs = 1200L
            if (noFaceMs >= patrolStartDelayMs) {
                if (!patrolMode) {
                    patrolMode = true
                    patrolDirection = if (currentPanAbs >= 0) -1f else 1f
                    lastPatrolCmdMs = 0L
                    filteredPan = 0f
                    filteredTilt = 0f
                    errIntX = 0f
                    errIntY = 0f
                    lastErrX = 0f
                    lastErrY = 0f
                    dispatchNativeEvent(
                        "state",
                        """{"status":"running","message":"No face detected. Starting patrol scan mode."}""",
                    )
                }
                if (currentPanAbs >= 480000) {
                    patrolDirection = -1f
                } else if (currentPanAbs <= -480000) {
                    patrolDirection = 1f
                }
                val patrolPan = (0.34f * patrolDirection).coerceIn(-0.45f, 0.45f)
                val patrolTilt =
                    when {
                        currentTiltAbs > 50000 -> -0.16f
                        currentTiltAbs < -50000 -> 0.16f
                        else -> 0f
                    }
                if (nowMs - lastPatrolCmdMs >= 420) {
                    lastPatrolCmdMs = nowMs
                    sendManualGimbalCommand(patrolPan, patrolTilt, 240)
                }
                dispatchEvent(
                    mapOf(
                        "type" to "telemetry",
                        "fps" to 0.0,
                        "latencyMs" to latencyMs,
                        "pan" to patrolPan.toDouble(),
                        "tilt" to patrolTilt.toDouble(),
                        "patrol" to true,
                        "source" to "yolov8n-face-tflite-libuvc",
                    ),
                )
                if (nowMs - lastPatrolNoticeMs > 2500) {
                    lastPatrolNoticeMs = nowMs
                    dispatchNativeEvent(
                        "state",
                        """{"status":"ready","message":"Patrol scan active (no face yet)."}""",
                    )
                }
                lastTelemetryMs = nowMs
                return
            }
            if (nowMs - lastNoFaceNoticeMs > 2500) {
                lastNoFaceNoticeMs = nowMs
                dispatchNativeEvent(
                    "state",
                    """{"status":"ready","message":"YOLO running but no face candidate yet. Move closer / center your face / improve lighting."}""",
                )
            }
            return
        }

        if (hasDetection) {
            dispatchEvent(
                mapOf(
                    "type" to "face",
                    "x" to detection!!.x.toDouble(),
                    "y" to detection.y.toDouble(),
                    "w" to detection.w.toDouble(),
                    "h" to detection.h.toDouble(),
                    "score" to detection.score.toDouble(),
                    "source" to "yolov8n-face-tflite-libuvc",
                ),
            )
        }

        val errX = faceCx - 0.5f
        val errY = faceCy - 0.5f
        val dt = max(0.05f, (nowMs - lastTelemetryMs).coerceAtLeast(1).toFloat() / 1000f)
        errIntX += errX * dt
        errIntY += errY * dt
        errIntX = errIntX.coerceIn(-1f, 1f)
        errIntY = errIntY.coerceIn(-1f, 1f)
        val dErrX = (errX - lastErrX) / dt
        val dErrY = (errY - lastErrY) / dt
        lastErrX = errX
        lastErrY = errY

        val panCmd = (-(pidKpX * errX + pidKiX * errIntX + pidKdX * dErrX)).coerceIn(-0.60f, 0.60f)
        val tiltCmd = (-(pidKpY * errY + pidKiY * errIntY + pidKdY * dErrY)).coerceIn(-0.45f, 0.45f)
        filteredPan = (filteredPan * 0.72f + panCmd * 0.28f).coerceIn(-0.60f, 0.60f)
        filteredTilt = (filteredTilt * 0.72f + tiltCmd * 0.28f).coerceIn(-0.45f, 0.45f)
        val panOut = if (abs(filteredPan) < 0.05f) 0f else filteredPan
        val tiltOut = if (abs(filteredTilt) < 0.05f) 0f else filteredTilt
        val fps = if (dt > 0f) (1f / dt) else 0f

        dispatchEvent(
            mapOf(
                "type" to "telemetry",
                "fps" to fps.toDouble(),
                "latencyMs" to latencyMs,
                "pan" to panOut.toDouble(),
                "tilt" to tiltOut.toDouble(),
                "source" to "yolov8n-face-tflite-libuvc",
            ),
        )
        lastTelemetryMs = nowMs

        if (nowMs - lastAutoGimbalMs < 220) {
            return
        }
        lastAutoGimbalMs = nowMs
        sendManualGimbalCommand(panOut, tiltOut, 240)
    }

    private fun activateCameraWithCamera2(): Boolean {
        if (captureSession != null && cameraDevice != null && imageReader != null) {
            isCameraActive = true
            return true
        }
        if (!ensureCameraPermission()) {
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Camera permission required for Camera2 path."}""",
            )
            return false
        }
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val pickedId = pickPreferredCameraId(cameraManager)
        if (pickedId == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No Camera2 camera available."}""",
            )
            return false
        }
        val chars = cameraManager.getCameraCharacteristics(pickedId)
        val cfg = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = cfg?.getOutputSizes(ImageFormat.YUV_420_888)?.toList() ?: emptyList()
        val size =
            sizes.firstOrNull { it.width == 1280 && it.height == 720 }
                ?: sizes.firstOrNull { it.width == 640 && it.height == 480 }
                ?: sizes.minByOrNull { it.width * it.height }
                ?: Size(640, 480)
        stopCamera2Pipeline()
        startCameraThread()
        val handler = cameraHandler
        if (handler == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Failed to create camera handler thread."}""",
            )
            return false
        }
        imageReader =
            ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 3).apply {
                setOnImageAvailableListener(
                    { reader ->
                        val img = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                        try {
                            cameraFramesSinceReport++
                            val now = System.currentTimeMillis()
                            if (cameraLastReportMs == 0L) {
                                cameraLastReportMs = now
                            }
                            if (now - cameraLastReportMs >= 1000) {
                                dispatchNativeEvent(
                                    "stream",
                                    """{"source":"camera2","frames":$cameraFramesSinceReport,"width":${img.width},"height":${img.height}}""",
                                )
                                Log.i(
                                    tag,
                                    "camera2Reader: frames=$cameraFramesSinceReport size=${img.width}x${img.height}",
                                )
                                cameraFramesSinceReport = 0
                                cameraLastReportMs = now
                            }
                        } finally {
                            img.close()
                        }
                    },
                    handler,
                )
            }

        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
            cameraManager.openCamera(
                pickedId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(device: CameraDevice) {
                        cameraDevice = device
                        val output = imageReader?.surface
                        if (output == null) {
                            dispatchNativeEvent(
                                "state",
                                """{"status":"error","message":"Camera2 ImageReader surface missing."}""",
                            )
                            return
                        }
                        createCamera2Session(device, output, handler)
                    }

                    override fun onDisconnected(device: CameraDevice) {
                        device.close()
                        if (cameraDevice === device) {
                            cameraDevice = null
                        }
                        dispatchNativeEvent(
                            "state",
                            """{"status":"error","message":"Camera2 external camera disconnected."}""",
                        )
                    }

                    override fun onError(device: CameraDevice, error: Int) {
                        device.close()
                        if (cameraDevice === device) {
                            cameraDevice = null
                        }
                        dispatchNativeEvent(
                            "state",
                            """{"status":"error","message":"Camera2 open error code=$error"}""",
                        )
                    }
                },
                handler,
            )
            dispatchNativeEvent(
                "state",
                """{"status":"ready","message":"Opening Camera2 camera id=$pickedId..."}""",
            )
            return true
        } catch (t: Throwable) {
            Log.e(tag, "activateCameraWithCamera2 failed", t)
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Camera2 activation exception: ${t.message ?: "unknown"}"}""",
            )
            return false
        }
    }

    private fun createCamera2Session(device: CameraDevice, outputSurface: Surface, handler: Handler) {
        try {
            val request =
                device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                    addTarget(outputSurface)
                    set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                }
            device.createCaptureSession(
                listOf(outputSurface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        try {
                            session.setRepeatingRequest(request.build(), null, handler)
                            isCameraActive = true
                            dispatchNativeEvent(
                                "state",
                                """{"status":"connected","message":"Camera2 stream active (external camera)."}""",
                            )
                        } catch (t: Throwable) {
                            Log.e(tag, "Camera2 setRepeatingRequest failed", t)
                            dispatchNativeEvent(
                                "state",
                                """{"status":"error","message":"Camera2 setRepeatingRequest failed: ${t.message ?: "unknown"}"}""",
                            )
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        dispatchNativeEvent(
                            "state",
                            """{"status":"error","message":"Camera2 capture session configure failed."}""",
                        )
                    }
                },
                handler,
            )
        } catch (t: Throwable) {
            Log.e(tag, "createCamera2Session failed", t)
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Camera2 session exception: ${t.message ?: "unknown"}"}""",
            )
        }
    }

    private fun startCameraThread() {
        if (cameraThread != null) {
            return
        }
        cameraThread = HandlerThread("ExternalCam2").apply { start() }
        cameraHandler = Handler(cameraThread!!.looper)
    }

    private fun stopCameraThread() {
        val t = cameraThread ?: return
        t.quitSafely()
        runCatching { t.join(500) }
        cameraThread = null
        cameraHandler = null
    }

    private fun stopCamera2Pipeline() {
        runCatching { captureSession?.close() }
        runCatching { cameraDevice?.close() }
        runCatching { imageReader?.close() }
        captureSession = null
        cameraDevice = null
        imageReader = null
        cameraFramesSinceReport = 0
        cameraLastReportMs = 0
        lastInferenceMs = 0
        lastTelemetryMs = 0
        lastAutoGimbalMs = 0
        stopCameraThread()
    }

    private fun pickPreferredCameraId(cameraManager: CameraManager): String? {
        var fallback: String? = null
        for (id in cameraManager.cameraIdList) {
            val chars = cameraManager.getCameraCharacteristics(id)
            val facing = chars.get(CameraCharacteristics.LENS_FACING)
            val caps = chars.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)
            Log.i(
                tag,
                "camera2 candidate id=$id facing=$facing caps=${caps.joinToString(",")}",
            )
            if (fallback == null) {
                fallback = id
            }
            if (facing == CameraCharacteristics.LENS_FACING_EXTERNAL) {
                return id
            }
        }
        return fallback
    }

    private fun chooseStreamParams(connection: UsbDeviceConnection): Triple<Int, Int, Int> {
        data class Candidate(val formatIndex: Int, val frameIndex: Int, val interval: Int, val mjpeg: Boolean)
        val raw = connection.rawDescriptors ?: return Triple(1, 1, 333333)
        val candidates = mutableListOf<Candidate>()
        var curFormatIndex = 1
        var curMjpeg = false
        var i = 0
        while (i + 2 < raw.size) {
            val len = raw[i].toInt() and 0xFF
            if (len <= 0 || i + len > raw.size) {
                break
            }
            val dtype = raw[i + 1].toInt() and 0xFF
            if (dtype == 0x24 && len >= 4) {
                when (raw[i + 2].toInt() and 0xFF) {
                    0x06 -> { // VS_FORMAT_MJPEG
                        curMjpeg = true
                        curFormatIndex = raw[i + 3].toInt() and 0xFF
                    }

                    0x04 -> { // VS_FORMAT_UNCOMPRESSED
                        curMjpeg = false
                        curFormatIndex = raw[i + 3].toInt() and 0xFF
                    }

                    0x07, // VS_FRAME_MJPEG
                    0x05 -> { // VS_FRAME_UNCOMPRESSED
                        val frameIndex = raw[i + 3].toInt() and 0xFF
                        val interval = if (len >= 25) u32le(raw, i + 21) else 333333
                        candidates.add(Candidate(curFormatIndex, frameIndex, interval, curMjpeg))
                    }
                }
            }
            i += len
        }
        val pick = candidates.firstOrNull { it.mjpeg } ?: candidates.firstOrNull()
        if (pick == null) {
            return Triple(1, 1, 333333)
        }
        return Triple(pick.formatIndex, pick.frameIndex, pick.interval)
    }

    private fun uvcProbeCommit(
        connection: UsbDeviceConnection,
        vsInterfaceId: Int,
        formatIndex: Int,
        frameIndex: Int,
        frameInterval100ns: Int,
    ): ByteArray? {
        val reqTypeOut = 0x21
        val reqTypeIn = 0xA1
        val setCur = 0x01
        val getCur = 0x81
        val vsProbe = 0x01
        val vsCommit = 0x02
        val lengths = intArrayOf(26, 34)
        for (len in lengths) {
            val probe = ByteArray(len)
            probe[0] = 1 // bmHint: use dwFrameInterval
            probe[2] = (formatIndex and 0xFF).toByte()
            probe[3] = (frameIndex and 0xFF).toByte()
            putU32le(probe, 4, frameInterval100ns)

            val setProbeRc =
                connection.controlTransfer(
                    reqTypeOut,
                    setCur,
                    vsProbe shl 8,
                    vsInterfaceId,
                    probe,
                    probe.size,
                    500,
                )
            val curProbe = ByteArray(len)
            val getProbeRc =
                connection.controlTransfer(
                    reqTypeIn,
                    getCur,
                    vsProbe shl 8,
                    vsInterfaceId,
                    curProbe,
                    curProbe.size,
                    500,
                )
            Log.i(
                tag,
                "uvcProbeCommit: len=$len setProbeRc=$setProbeRc getProbeRc=$getProbeRc",
            )
            if (setProbeRc < 0 || getProbeRc < 0) {
                continue
            }
            Log.i(tag, "uvcProbeCommit: curProbe=${summarizeProbe(curProbe)}")
            val setCommitRc =
                connection.controlTransfer(
                    reqTypeOut,
                    setCur,
                    vsCommit shl 8,
                    vsInterfaceId,
                    curProbe,
                    curProbe.size,
                    500,
                )
            Log.i(tag, "uvcProbeCommit: len=$len setCommitRc=$setCommitRc")
            if (setCommitRc >= 0) {
                return curProbe
            }
        }
        return null
    }

    private fun summarizeProbe(buf: ByteArray): String {
        val fmt = if (buf.size > 2) (buf[2].toInt() and 0xFF) else -1
        val frame = if (buf.size > 3) (buf[3].toInt() and 0xFF) else -1
        val interval = if (buf.size > 7) u32le(buf, 4) else -1
        val maxPayload = if (buf.size > 25) u32le(buf, 22) else -1
        return "fmt=$fmt frame=$frame interval=$interval maxPayload=$maxPayload len=${buf.size}"
    }

    private fun putU32le(buf: ByteArray, offset: Int, value: Int) {
        if (offset + 3 >= buf.size) {
            return
        }
        buf[offset] = (value and 0xFF).toByte()
        buf[offset + 1] = ((value ushr 8) and 0xFF).toByte()
        buf[offset + 2] = ((value ushr 16) and 0xFF).toByte()
        buf[offset + 3] = ((value ushr 24) and 0xFF).toByte()
    }

    private fun u32le(buf: ByteArray, offset: Int): Int {
        if (offset + 3 >= buf.size) {
            return 333333
        }
        return (buf[offset].toInt() and 0xFF) or
            ((buf[offset + 1].toInt() and 0xFF) shl 8) or
            ((buf[offset + 2].toInt() and 0xFF) shl 16) or
            ((buf[offset + 3].toInt() and 0xFF) shl 24)
    }

    private fun startStreamReader(): Boolean {
        val connection = usbConnection ?: return false
        val endpoint = activeStreamEndpoint ?: return false
        if (endpoint.direction != UsbConstants.USB_DIR_IN || endpoint.type != UsbConstants.USB_ENDPOINT_XFER_BULK) {
            Log.w(tag, "startStreamReader: unsupported endpoint type=${endpoint.type} dir=${endpoint.direction}")
            return false
        }
        stopStreamReader()
        streamReaderRunning.set(true)
        streamReaderThread =
            thread(name = "UvcBulkReader", isDaemon = true) {
                val buf = ByteArray((endpoint.maxPacketSize.coerceAtLeast(512)) * 8)
                var packets = 0L
                var bytes = 0L
                var payloadBytes = 0L
                var frames = 0L
                var lastReportMs = System.currentTimeMillis()
                var timeoutStreak = 0
                var requestMode = false
                var usbRequest: UsbRequest? = null
                while (streamReaderRunning.get()) {
                    try {
                        if (!requestMode) {
                            val rc = connection.bulkTransfer(endpoint, buf, buf.size, 1000)
                            if (rc > 0) {
                                timeoutStreak = 0
                                packets++
                                bytes += rc.toLong()
                                val headerLen = buf[0].toInt() and 0xFF
                                if (headerLen in 2..rc) {
                                    val payload = rc - headerLen
                                    if (payload > 0) {
                                        payloadBytes += payload.toLong()
                                    }
                                    val info = buf[1].toInt() and 0xFF
                                    if ((info and 0x02) != 0) {
                                        frames++
                                    }
                                }
                            } else {
                                timeoutStreak++
                                if (timeoutStreak >= 5) {
                                    usbRequest = UsbRequest().also { it.initialize(connection, endpoint) }
                                    requestMode = usbRequest != null
                                    Log.i(tag, "streamReader: switching to UsbRequest mode requestMode=$requestMode")
                                }
                            }
                        } else {
                            val req = usbRequest
                            if (req == null) {
                                requestMode = false
                            } else {
                                val bb = ByteBuffer.allocateDirect(buf.size)
                                val queued = req.queue(bb, buf.size)
                                if (!queued) {
                                    Log.w(tag, "streamReader: UsbRequest queue failed")
                                    requestMode = false
                                    req.close()
                                    usbRequest = null
                                } else {
                                    val completed = connection.requestWait(1000)
                                    if (completed == req) {
                                        val n = bb.position()
                                        if (n > 0) {
                                            packets++
                                            bytes += n.toLong()
                                        }
                                    }
                                }
                            }
                        }
                    } catch (t: Throwable) {
                        Log.w(tag, "streamReader: usb read exception ${t.message}")
                        requestMode = false
                        runCatching { usbRequest?.close() }
                        usbRequest = null
                        if (!streamReaderRunning.get()) {
                            break
                        }
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastReportMs >= 1000) {
                        val elapsed = (now - lastReportMs).coerceAtLeast(1)
                        val kbps = (bytes * 8.0 / elapsed)
                        dispatchNativeEvent(
                            "stream",
                            """{"packets":$packets,"bytes":$bytes,"payloadBytes":$payloadBytes,"frames":$frames,"kbps":$kbps}""",
                        )
                        Log.i(
                            tag,
                            "streamReader: packets=$packets bytes=$bytes payloadBytes=$payloadBytes frames=$frames kbps=$kbps",
                        )
                        packets = 0
                        bytes = 0
                        payloadBytes = 0
                        frames = 0
                        lastReportMs = now
                    }
                }
                usbRequest?.close()
                Log.i(tag, "streamReader: stopped")
            }
        return true
    }

    private fun stopStreamReader() {
        streamReaderRunning.set(false)
        streamReaderThread?.join(300)
        streamReaderThread = null
    }

    private fun claimVideoInterfaces(connection: UsbDeviceConnection, device: UsbDevice) {
        releaseClaimedInterfaces()
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_VIDEO) {
                val claimed = connection.claimInterface(intf, true)
                Log.i(
                    tag,
                    "claimVideoInterfaces: intf=$i subclass=${intf.interfaceSubclass} claimed=$claimed",
                )
                if (claimed) {
                    claimedInterfaces.add(intf)
                }
            }
        }
    }

    private fun releaseClaimedInterfaces() {
        val connection = usbConnection ?: return
        for (intf in claimedInterfaces) {
            runCatching { connection.releaseInterface(intf) }
        }
        claimedInterfaces.clear()
    }

    private fun sendManualGimbalCommand(
        pan: Float,
        tilt: Float,
        durationMs: Int,
        force: Boolean = false,
    ): Boolean {
        val connection = usbConnection
        val device = usbDevice
        if (connection == null || device == null) {
            Log.w(tag, "sendManualGimbalCommand: no usb connection")
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No USB connection for gimbal command."}""",
            )
            return false
        }
        if (!force && kotlin.math.abs(pan) < panDeadzone && kotlin.math.abs(tilt) < tiltDeadzone) {
            Log.i(
                tag,
                "sendManualGimbalCommand: ignored by deadzone pan=$pan tilt=$tilt dz=($panDeadzone,$tiltDeadzone)",
            )
            return true
        }
        val vcInterface = findVideoControlInterfaceNumber(device)
        if (vcInterface < 0) {
            Log.w(tag, "sendManualGimbalCommand: no VC interface")
            return false
        }

        val panMin = -522000
        val panMax = 522000
        val tiltMin = -324000
        val tiltMax = 360000

        // Use the exact Linux-captured tuple:
        // bmRequestType=0x21, bRequest=0x01, wValue=0x0d00, wIndex=0x0100, 8-byte payload [pan_i32_le, tilt_i32_le].
        // Direction convention here is camera-perspective (camera's left/right), not mirrored user-perspective.
        val panStep = (pan.coerceIn(-1f, 1f) * 90000f).roundToInt()
        val tiltStep = (tilt.coerceIn(-1f, 1f) * 68400f).roundToInt()
        currentPanAbs = (currentPanAbs + panStep).coerceIn(panMin, panMax)
        currentTiltAbs = (currentTiltAbs + tiltStep).coerceIn(tiltMin, tiltMax)
        val linuxPayload =
            ByteBuffer
                .allocate(8)
                .order(ByteOrder.LITTLE_ENDIAN)
                .putInt(currentPanAbs)
                .putInt(currentTiltAbs)
                .array()
        val linuxRc =
            connection.controlTransfer(
                0x21,
                0x01,
                0x0D00,
                0x0100,
                linuxPayload,
                linuxPayload.size,
                durationMs.coerceIn(80, 2000),
            )
        Log.i(
            tag,
            "PTZ SET_CUR linux-captured wIndex=0x0100 panAbs=$currentPanAbs tiltAbs=$currentTiltAbs rc=$linuxRc",
        )
        if (linuxRc >= 0) {
            dispatchNativeEvent(
                "state",
                """{"status":"connected","message":"PTZ command sent (linux tuple)."}""",
            )
            return true
        }
        dispatchNativeEvent(
            "state",
            """{"status":"error","message":"PTZ transfer failed on linux tuple path."}""",
        )
        return false
    }

    private fun sendManualZoomCommand(zoom: Float, durationMs: Int): Boolean {
        val connection = usbConnection ?: return false
        if (kotlin.math.abs(zoom) < 0.02f) {
            return true
        }
        val direction: Byte = if (zoom > 0f) 1 else (-1).toByte()
        val speed: Byte = (1 + (kotlin.math.abs(zoom).coerceIn(0f, 1f) * 7f).roundToInt()).toByte()
        // UVC CT_ZOOM_RELATIVE_CONTROL (selector 0x0C), 3-byte payload [direction, digitalZoom, speed]
        val payload = byteArrayOf(direction, 0, speed)
        val rc =
            connection.controlTransfer(
                0x21,
                0x01,
                0x0C00,
                0x0100,
                payload,
                payload.size,
                durationMs.coerceIn(80, 2000),
            )
        currentZoomLevel = (currentZoomLevel + zoom * 0.1f).coerceIn(-1f, 1f)
        if (rc >= 0) {
            dispatchNativeEvent(
                "state",
                """{"status":"connected","message":"Zoom command sent."}""",
            )
            return true
        }
        dispatchNativeEvent(
            "state",
            """{"status":"ready","message":"Zoom command not supported by current camera control path."}""",
        )
        return false
    }

    private fun readAbsolutePtzPair(
        connection: UsbDeviceConnection,
        selector: Int,
        entityId: Int,
        vcInterface: Int,
        request: Int,
    ): Pair<Int, Int>? {
        val reqTypeIn = 0xA1
        val buf = ByteArray(8)
        val rc =
            connection.controlTransfer(
                reqTypeIn,
                request,
                selector shl 8,
                (entityId shl 8) or (vcInterface and 0xFF),
                buf,
                buf.size,
                200,
            )
        if (rc < 8) {
            return null
        }
        val bb = ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN)
        return Pair(bb.int, bb.int)
    }

    private fun lerpSignedRange(value: Float, min: Int, max: Int): Int {
        val v = value.coerceIn(-1f, 1f)
        val mid = (min.toLong() + max.toLong()) / 2.0
        val half = (max.toLong() - min.toLong()) / 2.0
        return (mid + (half * v)).roundToInt()
    }

    private fun findVideoControlInterfaceNumber(device: UsbDevice): Int {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_VIDEO && intf.interfaceSubclass == 1) {
                return intf.id
            }
        }
        return -1
    }

    private fun isCenterCommand(pan: Float, tilt: Float): Boolean {
        return kotlin.math.abs(pan) < 0.02f && kotlin.math.abs(tilt) < 0.02f
    }

    private fun findPtzEntityCandidates(connection: UsbDeviceConnection): List<Int> {
        val raw = connection.rawDescriptors ?: return emptyList()
        val out = linkedSetOf<Int>()
        var i = 0
        while (i + 2 < raw.size) {
            val len = raw[i].toInt() and 0xFF
            if (len <= 0 || i + len > raw.size) {
                break
            }
            val dtype = raw[i + 1].toInt() and 0xFF
            if (dtype == 0x24 && len >= 4) {
                val subtype = raw[i + 2].toInt() and 0xFF
                if (subtype == 0x02 && len >= 8) {
                    val terminalId = raw[i + 3].toInt() and 0xFF
                    val wTerminalType =
                        (raw[i + 4].toInt() and 0xFF) or ((raw[i + 5].toInt() and 0xFF) shl 8)
                    if (wTerminalType == 0x0201) {
                        out.add(terminalId)
                    }
                } else if (subtype == 0x06) {
                    out.add(raw[i + 3].toInt() and 0xFF)
                }
            }
            i += len
        }
        Log.i(tag, "findPtzEntityCandidates: $out")
        return out.toList()
    }

    private fun dispatchEvent(map: Map<String, Any>) {
        mainHandler.post {
            Log.i(tag, "event=$map")
            eventSink?.success(map)
        }
    }

    companion object {
        init {
            System.loadLibrary("native_tracker")
        }

        @Volatile
        private var instance: MainActivity? = null

        @JvmStatic
        fun dispatchNativeEvent(type: String, payload: String) {
            val host = instance ?: return
            val message = mutableMapOf<String, Any>("type" to type)
            try {
                val json = JSONObject(payload)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    message[key] = json.get(key)
                }
            } catch (_: Throwable) {
                message["payload"] = payload
            }
            host.dispatchEvent(message)
        }
    }
}
