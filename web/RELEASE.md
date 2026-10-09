# Browser release: character, mode and sample library update

- Four 3D presets (three additional presets): classic headphones sphere, mint beanie bean, pink long-ear bunny and crowned rounded square with round glasses.
- Four original, on-demand, 12-second synthesized test tracks (three additional arrangements): 120 BPM melodic, 80 BPM ambient, 140 BPM electronic and 90 BPM vowel-like phrase. Each in-memory WAV is 576,044 bytes. No commercial recording or real singer is included.
- Singer mode analyzes 300–3000 Hz mixture energy and spectral center; background mode analyzes 40–300 Hz energy, positive changes and mixture level. Their axes and spectrum bands differ. Neither is AI, vocal separation, pitch detection or learned beat tracking. Switching modes reuses audio and smooths the existing pose.
- TypeScript check and production build passed. Fifteen unit tests passed, including band-specific response and distinct PCM arrangements. The isolated local production browser regression passed four live preset changes, repeated mode switches, four live track changes, active spectrum, playback/pause, two file replacements, audio end/replay, mobile overflow and teardown. Character screenshots were inspected.
- Current static dist: 528,832 bytes, maximum file 521,476 bytes (JS). No ONNX model, WASM runtime or uploaded user audio is bundled. Build emits the informational >500 kB chunk warning; gzip JS is about 135 kB.

Public deployment status is verified separately against the exact gh-pages commit and official Pages build run; local test results alone do not prove rollout.
