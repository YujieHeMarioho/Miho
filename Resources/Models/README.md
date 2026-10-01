# BeatNet model

`beatnet.onnx` is a state-explicit conversion of Mojtaba Heydari's BeatNet model-2 checkpoint, licensed CC BY 4.0. Preserve [attribution and license](../../ThirdParty/README.md) when distributing it. The graph has not been retrained. Input: `features[1,1,272]`, `hidden[2,1,150]`, `cell[2,1,150]`; outputs: `probabilities[3]` (beat/downbeat/neither) and both next states.

Developer reproduction (not required to build or run the app):

```bash
python3 -m venv dist/beat-export-env
source dist/beat-export-env/bin/activate
pip install -r scripts/beat-export-requirements.txt
curl --fail --location --output dist/model_2_weights.pt https://raw.githubusercontent.com/mjhydri/BeatNet/81cedd4beeb7235262db80969a0c9ce9a48a0ed4/src/BeatNet/models/model_2_weights.pt
python scripts/export-beat-model.py dist/model_2_weights.pt
```

The exporter checks the checkpoint SHA-256, exports ONNX, verifies thirty recurrent frames against PyTorch, writes native filter coefficients and produces synthetic parity fixtures. The exported hash is recorded in ThirdParty/README.md and checked by the native host. PyTorch/ONNX tool changes can change serialized graph bytes; do not update the expected hash without verifying outputs and licensing.
