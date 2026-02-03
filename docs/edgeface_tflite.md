# EdgeFace-S to TFLite (Local Build Notes)

This document explains how to download EdgeFace-S weights and convert them to
`edgeface_s.tflite` for local use in this project. This file is safe to keep in
the repo; the model artifacts themselves should stay local.

## 1) Download EdgeFace-S checkpoint (PyTorch)

From the official EdgeFace repository, the EdgeFace-S (gamma=0.5) checkpoint is:
`checkpoints/edgeface_s_gamma_05.pt`.

Example download (GitHub raw):
```bash
curl -L -o edgeface_s_gamma_05.pt \
  https://github.com/otroshi/edgeface/raw/main/checkpoints/edgeface_s_gamma_05.pt
```

## 2) Export to ONNX (legacy exporter)

Use `torch.hub` to load the model and export to ONNX. Use the legacy exporter
(`dynamo=False`) to avoid `SequenceEmpty` issues during conversion.

`export_edgeface_onnx.py`:
```python
import torch

model = torch.hub.load("otroshi/edgeface", "edgeface_s_gamma_05", pretrained=True)
model.eval()

dummy = torch.randn(1, 3, 112, 112)
torch.onnx.export(
    model,
    dummy,
    "edgeface_s_gamma_05_legacy.onnx",
    input_names=["input"],
    output_names=["embedding"],
    opset_version=17,
    dynamo=False,
)
```

Run:
```bash
python export_edgeface_onnx.py
```

## 3) Convert ONNX -> TFLite (onnx2tflite)

The most reliable conversion for this model uses `onnx2tflite` (from the
`eiq-onnx2tflite` package) and keeps NCHW input/output formats.

Install:
```bash
python -m pip install --extra-index-url https://eiq.nxp.com/repository/ eiq-onnx2tflite
```

Convert (this produces NHWC inputs, matching the Android embedder):
```bash
python -m onnx2tflite edgeface_s_gamma_05_legacy.onnx \
  --set-input-shape "input:(1,3,112,112)" \
  -o edgeface_s.tflite -v
```

Place the model in this project:
```bash
copy edgeface_s.tflite android/app/src/main/assets/models/edgeface_s.tflite
```

## 4) Preprocessing notes

EdgeFace uses face alignment and the standard normalization:
`(x - 0.5) / 0.5` (equivalent to mean=0.5, std=0.5 per channel).
This matches the current normalization in the Android embedder.

## 5) Troubleshooting

- If conversion fails, confirm the ONNX input is `1x3x112x112` and named `input`.
- If you must keep NCHW inputs, add `--keep-io-tensors-format` and update the
  Android embedder to feed NCHW tensors.
- If accuracy looks off, verify alignment and normalization.
