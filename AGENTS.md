# AGENTS.md

## Quick dev notes

- If only Flutter UI/layout changes are made, prefer `flutter run` + hot-reload (`r`) instead of rebuilding APKs.
- Rebuild/reinstall only when native (Kotlin/C++) code changes or hot-reload cannot apply.

## HOW TO (Flutter/Android)
- UI-only changes:
  - `flutter run`
  - press `r` for hot-reload
- Native changes (Kotlin/C++):
  - `flutter analyze`
  - `flutter build apk --debug`
  - `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- Useful adb:
  - `adb devices -l`
  - `adb logcat -c`
