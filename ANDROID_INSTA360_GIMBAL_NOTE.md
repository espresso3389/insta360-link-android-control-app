# Insta360 Link Gimbal Control on Android (libuvc/libusb + Packet Findings)

## Scope
This note captures the final working path for Insta360 Link gimbal control on Android in this repository, including:
- native build integration (`libusb` + `libuvc`)
- USB/UVC packet findings from baseline capture
- Android replay implementation details
- operational commands and troubleshooting

---

## Repository Context

- Android app package: `com.example.insta360link_android_test`
- Main native bridge:
  - `android/app/src/main/kotlin/com/example/insta360link_android_test/MainActivity.kt`
  - `android/app/src/main/cpp/native_tracker.cpp`
  - `android/app/src/main/cpp/CMakeLists.txt`

---

## 1) Native Build: libusb + libuvc

### Vendored sources
- `third_party/libusb`
- `third_party/libuvc`

### CMake integration
File: `android/app/src/main/cpp/CMakeLists.txt`

Key points:
- Builds `libusb_static` from Android/Linux usbfs backend sources.
- Builds `libuvc_static` from libuvc core sources.
- Links both static libs into `native_tracker`.
- Generates `libuvc_config.h` from `libuvc_config.h.in`.

This enables:
- `uvc_wrap(fd, ...)` with Android USB file descriptor from Java layer.
- real UVC stream callbacks in native.

---

## 2) Camera Streaming Path (Android)

### Why Java bulk reader was insufficient
Earlier Java-side stream reader produced repeated read exceptions / no payload.

### Current working approach
In `native_tracker.cpp`:
- Initialize `libusb` context with no-discovery init option.
- Initialize `libuvc` with that context.
- Wrap Android USB FD (`uvc_wrap`).
- Start stream (`uvc_start_streaming`).
- Run dedicated libusb event loop thread (`libusb_handle_events_timeout_completed`) so callbacks fire.

Result:
- Non-zero stream telemetry (`frames`, `bytes`, `kbps`) from source `libuvc`.

---

## 3) Critical Gimbal Finding

## ✅ Correct packet tuple came from baseline capture

- `bmRequestType = 0x21`
- `bRequest = 0x01` (`SET_CUR`)
- `wValue = 0x0D00` (CT_PANTILT_ABSOLUTE_CONTROL selector)
- `wIndex = 0x0100`
- payload length = `8`
- payload layout = little-endian `int32 pan`, `int32 tilt`

This is the key difference from many failed attempts:
- Generic entity-targeted indexes like `(entity << 8) | vcIf` often ACKed but produced tilt-only / recenter behavior.
- The fixed `wIndex=0x0100` tuple produced real yaw/pan on Android.

---

## 4) Final Android Gimbal Control Logic

File: `android/app/src/main/kotlin/com/example/insta360link_android_test/MainActivity.kt`

Method: `sendManualGimbalCommand(...)`

Current behavior:
- Uses only the confirmed working tuple (`0x21/0x01/0x0D00/0x0100`).
- Builds payload as:
  - `panAbs` (`int32 LE`)
  - `tiltAbs` (`int32 LE`)
- Updates absolute state using incremental steps from normalized input:
  - pan step: `panNorm * 90000`
  - tilt step: `tiltNorm * 68400` (matches observed Linux rounded step)
- clamps to:
  - pan: `[-522000, 522000]`
  - tilt: `[-324000, 360000]`

### Center fix
`pan=0, tilt=0` now forces real center packet:
- resets `currentPanAbs=0`, `currentTiltAbs=0`
- bypasses deadzone suppression via `force=true`

This was required because deadzone filtering previously caused "center" to be ignored.

### Direction convention
- Left/Right movement is defined in **camera-perspective** (camera's own left/right), not mirror/selfie perspective.
- Keep this in mind when labeling UI controls and evaluating tracking behavior.

---

## 5) ADB Commands (Current Useful Set)

### Build / install
```powershell
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### Device setup
```powershell
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd connect --ei vid 11802 --ei pid 19457
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd activate
```

### Manual gimbal
```powershell
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd manual --ef pan -1.0 --ef tilt 0.0 --ei durationMs 800
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd manual --ef pan 0.0 --ef tilt 0.0 --ei durationMs 700
```

### Linux baseline replay (debug)
```powershell
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd replaylinux
```

### Script helper
```powershell
.\scripts\adb_camctl.ps1 -Cmd connect -VendorId 11802 -ProductId 19457
.\scripts\adb_camctl.ps1 -Cmd activate
.\scripts\adb_camctl.ps1 -Cmd manual -Pan -1 -Tilt 0 -DurationMs 800
.\scripts\adb_camctl.ps1 -Cmd replaylinux
```

---

## 6) Flutter UI Changes

Files:
- `lib/src/insta_link_tracker.dart`
- `lib/src/tracking_page.dart`

Added:
- `activateCamera()` and `manualControl(...)` method-channel APIs.
- gimbal preset card: `Up/Left/Center/Right/Down`.
- tracking-to-gimbal link toggle.
- optional telemetry-driven gimbal updates when tracking is running.

---

## 7) What Failed (for future reference)

These paths often returned success codes but did not provide stable yaw:
- entity-indexed UVC PTZ writes (e.g. unit 9/10/11 with varying `wIndex` strategies)
- many XU selector probes with accepted writes but no yaw output
- swapped axis payload variants without Linux tuple match

Takeaway:
- for this camera on Android host USB path, packet acceptance != correct motion.
- exact on-wire tuple matching was required.

---

## 8) Known Good Validation Signal

In logcat (`InstaLinkTracker`), successful manual command should show:
- `PTZ SET_CUR linux-captured wIndex=0x0100 ... rc=8`
- followed by state event:
  - `PTZ command sent (linux tuple).`

Center command should show:
- `panAbs=0 tiltAbs=0`

---

## 9) Recommended Next Cleanup

If desired, simplify further:
- remove old probe/research commands (`probeptz`, `dumpxu`, `probexu`) from production branch.
- keep `replaylinux` only as debug.
- add persistent calibration UI:
  - "Set Current as Center"
  - "Go Center"
- tune telemetry->gimbal gain/rate for smoother tracking.

---

## Summary
The working Android gimbal solution is now:
1. native `libusb/libuvc` integration for robust UVC stream handling.
2. gimbal PTZ control using Linux-captured exact UVC control tuple:
   - `0x21 / 0x01 / 0x0D00 / 0x0100` with 8-byte `(pan_i32_le, tilt_i32_le)`.
3. explicit center handling to ensure reliable recentering.
