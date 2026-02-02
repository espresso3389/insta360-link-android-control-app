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
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
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
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var cameraFramesSinceReport = 0L
    private var cameraLastReportMs = 0L

    private external fun nativeInit(): Boolean
    private external fun nativeAttachUsbFd(fd: Int, vid: Int, pid: Int): Boolean
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
        } else {
            registerReceiver(usbPermissionReceiver, IntentFilter(usbPermissionAction))
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
                if (!isCameraActive && !activateCameraStreamInterface()) {
                    result.success(false)
                } else {
                    result.success(nativeStartTracking())
                }
            }
            "stopTracking" -> result.success(nativeStopTracking())
            "setPid" -> {
                val args = call.arguments as? Map<*, *>
                val kpX = (args?.get("kpX") as? Number)?.toFloat() ?: 0f
                val kiX = (args?.get("kiX") as? Number)?.toFloat() ?: 0f
                val kdX = (args?.get("kdX") as? Number)?.toFloat() ?: 0f
                val kpY = (args?.get("kpY") as? Number)?.toFloat() ?: 0f
                val kiY = (args?.get("kiY") as? Number)?.toFloat() ?: 0f
                val kdY = (args?.get("kdY") as? Number)?.toFloat() ?: 0f
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
                val ok = sendManualGimbalCommand(pan, tilt, durationMs)
                nativeManualControl(pan, tilt, durationMs)
                result.success(ok)
            }

            "activateCamera" -> result.success(activateCameraStreamInterface())

            "dispose" -> {
                stopAndDetachUsb()
                result.success(nativeDispose())
            }

            else -> result.notImplemented()
        }
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
        Log.i(tag, "connectUsbDevice: connected vid=$vid pid=$pid fd=${connection.fileDescriptor}")
        dispatchNativeEvent("state", """{"status":"connected","message":"USB device connected."}""")
        return true
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
        stopStreamReader()
        nativeStopTracking()
        nativeDetachUsb()
        releaseClaimedInterfaces()
        usbConnection?.close()
        usbConnection = null
        usbDevice = null
        activeStreamEndpoint = null
        isCameraActive = false
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
                if (!isCameraActive && !activateCameraStreamInterface()) {
                    return
                }
                nativeStartTracking()
            }
            "stop" -> nativeStopTracking()
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
                sendManualGimbalCommand(pan, tilt, durationMs)
                nativeManualControl(pan, tilt, durationMs)
            }

            "activate" -> activateCameraStreamInterface()
        }
    }

    private fun activateCameraStreamInterface(): Boolean {
        val connection = usbConnection
        val device = usbDevice
        if (connection == null || device == null) {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No USB connection. Run connect first."}""",
            )
            return false
        }

        val vsInterfaces =
            (0 until device.interfaceCount)
                .map { device.getInterface(it) }
                .filter {
                    it.interfaceClass == UsbConstants.USB_CLASS_VIDEO && it.interfaceSubclass == 2
                }
        for (intf in vsInterfaces) {
            val eps =
                (0 until intf.endpointCount).joinToString(";") { ei ->
                    val ep = intf.getEndpoint(ei)
                    "addr=${ep.address},type=${ep.type},dir=${ep.direction},mps=${ep.maxPacketSize}"
                }
            Log.i(
                tag,
                "activateCamera: vs intf id=${intf.id} alt=${intf.alternateSetting} eps=${intf.endpointCount} [$eps]",
            )
        }
        if (vsInterfaces.isEmpty()) {
            isCameraActive = false
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No UVC VS interfaces found."}""",
            )
            return false
        }

        val controlAlt =
            vsInterfaces.firstOrNull { it.endpointCount == 0 } ?: vsInterfaces.first()
        val vsInterfaceId = controlAlt.id
        val (formatIndex, frameIndex, frameInterval100ns) = chooseStreamParams(connection)
        Log.i(
            tag,
            "activateCamera: stream params format=$formatIndex frame=$frameIndex interval100ns=$frameInterval100ns",
        )

        val probeData = uvcProbeCommit(connection, vsInterfaceId, formatIndex, frameIndex, frameInterval100ns)
        if (probeData == null) {
            isCameraActive = false
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"UVC PROBE/COMMIT failed."}""",
            )
            return false
        }

        var chosenStreamAlt: UsbInterface? = null
        var chosenEp: UsbEndpoint? = null
        var bestScore = -1
        for (intf in vsInterfaces) {
            if (intf.id != vsInterfaceId || intf.endpointCount == 0) {
                continue
            }
            for (e in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(e)
                if (ep.direction != UsbConstants.USB_DIR_IN) {
                    continue
                }
                val score = ep.maxPacketSize + if (ep.type == UsbConstants.USB_ENDPOINT_XFER_ISOC) 100000 else 0
                if (score > bestScore) {
                    bestScore = score
                    chosenStreamAlt = intf
                    chosenEp = ep
                }
            }
        }

        if (chosenStreamAlt == null) {
            isCameraActive = false
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"No UVC VS stream alternate setting found."}""",
            )
            return false
        }

        val claimedControl = connection.claimInterface(controlAlt, true)
        val setControlOk = connection.setInterface(controlAlt)
        val claimedStream = connection.claimInterface(chosenStreamAlt, true)
        val setStreamOk = connection.setInterface(chosenStreamAlt)
        Log.i(
            tag,
            "activateCamera: vsIf=$vsInterfaceId controlAlt=${controlAlt.alternateSetting} claimedControl=$claimedControl setControl=$setControlOk streamAlt=${chosenStreamAlt.alternateSetting} claimedStream=$claimedStream setStream=$setStreamOk epType=${chosenEp?.type} epAddr=${chosenEp?.address} epMax=${chosenEp?.maxPacketSize}",
        )

        if (!claimedControl || !setControlOk || !claimedStream || !setStreamOk) {
            isCameraActive = false
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"Failed to set UVC stream alternate setting."}""",
            )
            return false
        }

        activeStreamEndpoint = chosenEp
        val readerStarted = startStreamReader()
        if (chosenEp != null && chosenEp.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
            val tmp = ByteArray(1024)
            val rc = connection.bulkTransfer(chosenEp, tmp, tmp.size, 200)
            Log.i(tag, "activateCamera: bulk probe rc=$rc")
        }

        dispatchNativeEvent(
            "state",
            """{"status":"connected","message":"UVC stream active (if=$vsInterfaceId, alt=${chosenStreamAlt.alternateSetting}, fmt=$formatIndex, frame=$frameIndex, reader=$readerStarted)."}""",
        )
        isCameraActive = true
        return true
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

    private fun sendManualGimbalCommand(pan: Float, tilt: Float, durationMs: Int): Boolean {
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
        val vcInterface = findVideoControlInterfaceNumber(device)
        if (vcInterface < 0) {
            Log.w(tag, "sendManualGimbalCommand: no VC interface")
            return false
        }

        val parsedEntities = findPtzEntityCandidates(connection)
        val entities = if (parsedEntities.isEmpty()) listOf(1, 2, 3, 4, 5, 6) else parsedEntities
        val selector = 0x0D // CT_PANTILT_ABSOLUTE_CONTROL
        val reqTypeOut = 0x21
        val reqTypeIn = 0xA1
        val setCur = 0x01
        val getInfo = 0x86
        val getMin = 0x82
        val getMax = 0x83
        val panScales = intArrayOf(36000, 648000, 3600)
        var succeeded = false

        for (entityId in entities) {
            val infoBuf = ByteArray(1)
            val infoRc =
                connection.controlTransfer(
                    reqTypeIn,
                    getInfo,
                    selector shl 8,
                    (entityId shl 8) or (vcInterface and 0xFF),
                    infoBuf,
                    infoBuf.size,
                    200,
                )
            Log.i(
                tag,
                "PTZ GET_INFO abs entity=$entityId vcIf=$vcInterface rc=$infoRc info=${if (infoRc > 0) infoBuf[0].toInt() and 0xFF else -1}",
            )
            val minAbs = readAbsolutePtzPair(connection, selector, entityId, vcInterface, getMin)
            val maxAbs = readAbsolutePtzPair(connection, selector, entityId, vcInterface, getMax)
            Log.i(
                tag,
                "PTZ RANGE abs entity=$entityId min=$minAbs max=$maxAbs",
            )

            if (
                minAbs != null &&
                    maxAbs != null &&
                    (minAbs.first != maxAbs.first || minAbs.second != maxAbs.second)
            ) {
                val panRaw = lerpSignedRange(pan, minAbs.first, maxAbs.first)
                val tiltRaw = lerpSignedRange(tilt, minAbs.second, maxAbs.second)
                val payload =
                    ByteBuffer
                        .allocate(8)
                        .order(ByteOrder.LITTLE_ENDIAN)
                        .putInt(panRaw)
                        .putInt(tiltRaw)
                        .array()
                val mappedRc =
                    connection.controlTransfer(
                        reqTypeOut,
                        setCur,
                        selector shl 8,
                        (entityId shl 8) or (vcInterface and 0xFF),
                        payload,
                        payload.size,
                        durationMs.coerceIn(50, 2000),
                    )
                Log.i(
                    tag,
                    "PTZ SET_CUR abs(mapped) entity=$entityId panRaw=$panRaw tiltRaw=$tiltRaw rc=$mappedRc",
                )
                if (mappedRc >= 0) {
                    succeeded = true
                }
            }

            if (succeeded) {
                break
            }
            for (scale in panScales) {
                val panRaw = (pan.coerceIn(-1f, 1f) * scale).roundToInt()
                val tiltRaw = (tilt.coerceIn(-1f, 1f) * scale).roundToInt()
                val payload =
                    ByteBuffer
                        .allocate(8)
                        .order(ByteOrder.LITTLE_ENDIAN)
                        .putInt(panRaw)
                        .putInt(tiltRaw)
                        .array()
                val wValue = selector shl 8
                val wIndex = (entityId shl 8) or (vcInterface and 0xFF)
                val rc =
                    connection.controlTransfer(
                        reqTypeOut,
                        setCur,
                        wValue,
                        wIndex,
                        payload,
                        payload.size,
                        durationMs.coerceIn(50, 2000),
                    )
                Log.i(
                    tag,
                    "PTZ SET_CUR abs entity=$entityId vcIf=$vcInterface scale=$scale panRaw=$panRaw tiltRaw=$tiltRaw rc=$rc",
                )
                if (rc >= 0) {
                    succeeded = true
                    break
                }
            }
            if (!succeeded) {
                val relSelector = 0x0E // CT_PANTILT_RELATIVE_CONTROL
                val panDir = if (pan > 0.05f) 1 else if (pan < -0.05f) -1 else 0
                val tiltDir = if (tilt > 0.05f) 1 else if (tilt < -0.05f) -1 else 0
                val panSpeed = (pan.coerceIn(-1f, 1f).let { kotlin.math.abs(it) } * 7f).roundToInt().coerceIn(0, 7)
                val tiltSpeed = (tilt.coerceIn(-1f, 1f).let { kotlin.math.abs(it) } * 7f).roundToInt().coerceIn(0, 7)
                val relPayload =
                    byteArrayOf(
                        panDir.toByte(),
                        panSpeed.toByte(),
                        tiltDir.toByte(),
                        tiltSpeed.toByte(),
                    )
                val relRc =
                    connection.controlTransfer(
                        reqTypeOut,
                        setCur,
                        relSelector shl 8,
                        (entityId shl 8) or (vcInterface and 0xFF),
                        relPayload,
                        relPayload.size,
                        durationMs.coerceIn(50, 2000),
                    )
                Log.i(
                    tag,
                    "PTZ SET_CUR rel entity=$entityId vcIf=$vcInterface panDir=$panDir panSpeed=$panSpeed tiltDir=$tiltDir tiltSpeed=$tiltSpeed rc=$relRc",
                )
                if (relRc >= 0) {
                    succeeded = true
                }
            }
            if (succeeded) {
                break
            }
        }

        if (succeeded) {
            dispatchNativeEvent(
                "state",
                """{"status":"connected","message":"PTZ command sent (experimental UVC path)."}""",
            )
        } else {
            dispatchNativeEvent(
                "state",
                """{"status":"error","message":"PTZ transfer failed on tested entities."}""",
            )
        }
        return succeeded
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
