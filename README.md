# insta360link_android_test

Flutter + Android native (JNI/C++) starter for Insta360 Link face-tracking control.

## Docs

- `docs/android_insta360link_gimbal.md` (gimbal control + packet findings)
- `docs/edgeface_tflite.md` (EdgeFace-S export to TFLite)
- `docs/yolo_v8_face.md` (YOLOv8n-face model notes)

## ADB-first control

You can drive the app without touching the UI by sending commands to `MainActivity`.

### Build/install

```sh
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### Direct commands

```sh
# Initialize
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd init

# List USB devices (logs via logcat tag Insta360LinkTracker)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd list

# Connect by VID/PID
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd connect --ei vid 11802 --ei pid 19457

# Start / Stop tracking
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd start
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd stop

# Tune PID gains live (no rebuild)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd setpid --ef kpX -1.2 --ef kiX 0.0 --ef kdX -0.12 --ef kpY 1.0 --ef kiY 0.0 --ef kdY 0.10

# Activate UVC stream (PROBE/COMMIT + stream alt selection)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd activate

# Activate Android Camera2 external-camera stream fallback
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd activate2

# Manual pan/tilt command hook (currently telemetry/state hook)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd manual --ef pan 0.2 --ef tilt -0.1 --ei durationMs 400

# Manual zoom command (best-effort UVC relative zoom)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd zoom --ef zoom 1.0 --ei durationMs 400

# Replay Linux-captured PTZ baseline packets
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd replaylinux
```

### Helper script

Use `scripts/adb_camctl.ps1` to run command + fetch logs:

```powershell
.\scripts\adb_camctl.ps1 -Cmd list
.\scripts\adb_camctl.ps1 -Cmd connect -VendorId 11802 -ProductId 19457
.\scripts\adb_camctl.ps1 -Cmd activate
.\scripts\adb_camctl.ps1 -Cmd activate2
.\scripts\adb_camctl.ps1 -Cmd setpid -KpX -1.2 -KiX 0 -KdX -0.12 -KpY 1.0 -KiY 0 -KdY 0.10
.\scripts\adb_camctl.ps1 -Cmd start
.\scripts\adb_camctl.ps1 -Cmd manual -Pan 0.2 -Tilt -0.1 -DurationMs 400
.\scripts\adb_camctl.ps1 -Cmd zoom -Zoom 1.0 -DurationMs 400
.\scripts\adb_camctl.ps1 -Cmd replaylinux
.\scripts\adb_camctl.ps1 -Cmd stop
```

### Direction convention

- Left/Right is **camera-perspective** (the camera's own left/right), not mirror/selfie perspective.
- Example: manual `pan -1` means "move to camera-left".

## App UX behavior

- On app launch, it automatically runs: `init -> connect first UVC device -> start tracking`.
- Manual pan/tilt/zoom commands switch the app to **Manual** mode (automatic tracking stops).
- Automatic tracking resumes only when the user presses **Automatic** in the app.
- Zoom is sent with a best-effort UVC relative zoom command and may vary by camera firmware/control path.
