# insta360link_android_test

Flutter + Android native (JNI/C++) starter for Insta360 Link face-tracking control.

## ADB-first control

You can drive the app without touching the UI by sending commands to `MainActivity`.

### Build/install

```powershell
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### Direct commands

```powershell
# Initialize
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd init

# List USB devices (logs via logcat tag InstaLinkTracker)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd list

# Connect by VID/PID
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd connect --ei vid 11802 --ei pid 19457

# Start / Stop tracking
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd start
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd stop

# Activate UVC stream (PROBE/COMMIT + stream alt selection)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd activate

# Manual pan/tilt command hook (currently telemetry/state hook)
adb shell am start -n com.example.insta360link_android_test/.MainActivity --es cmd manual --ef pan 0.2 --ef tilt -0.1 --ei durationMs 400
```

### Helper script

Use `scripts/adb_camctl.ps1` to run command + fetch logs:

```powershell
.\scripts\adb_camctl.ps1 -Cmd list
.\scripts\adb_camctl.ps1 -Cmd connect -VendorId 11802 -ProductId 19457
.\scripts\adb_camctl.ps1 -Cmd activate
.\scripts\adb_camctl.ps1 -Cmd start
.\scripts\adb_camctl.ps1 -Cmd manual -Pan 0.2 -Tilt -0.1 -DurationMs 400
.\scripts\adb_camctl.ps1 -Cmd stop
```
