# YOLOv8n-face (TFLite) notes

This app tracks faces using `yolov8n-face.tflite`.

Runtime lookup order:
- `android/app/src/main/assets/models/yolov8n-face.tflite` (packaged in APK)
- `/sdcard/Download/yolov8n-face.tflite` (device-side fallback)

Current tracking pipeline:
- libuvc stream (Insta360 Link) -> YOLOv8n-face TFLite
- detected face center -> PID pan/tilt command
- gimbal PTZ via `0x21/0x01/0x0D00/0x0100`

## Easiest: download prebuilt model from GitHub Releases

Release tag: `models-v2026-02-02`
- `yolov8n-face_float32.tflite`
- release page: https://github.com/espresso3389/insta360-link-android-control-app/releases/tag/models-v2026-02-02

Copy to app assets directory; `android/app/src/main/assets/models/`

Or push to device fallback path:

```sh
adb push yolov8n-face_float32.tflite /sdcard/Download/yolov8n-face.tflite
```

## Manual build (.pt -> .tflite)

```sh
# 1) Create Python 3.11 env for export
uv python install 3.11
uv venv .modelbuild\venv --python 3.11

# 2) Install exporter deps
uv pip install --python .modelbuild\venv\Scripts\python.exe ultralytics tensorflow==2.19.0

# 3) Download source weights (example known-good yolov8n-face.pt)
python -m gdown --id 1qcr9DbgsX3ryrz2uU8w4Xm3cOrRywXqb -O yolov8n-face.pt

# 4) Export TFLite
python -c "from ultralytics import YOLO; m = YOLO('yolov8n-face.pt'); print(m.export(format='tflite', imgsz=320))"
```

Expected output:
- `yolov8n-face_saved_model\yolov8n-face_float32.tflite`

Then copy it to:
- `android/app/src/main/assets/models/yolov8n-face.tflite`
