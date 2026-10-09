# Miho browser experience

The browser companion renders a procedural 3D spherical Miho with short ears, brown headphones and black glasses. It analyzes browser-local audio with Web Audio and animates the character and spectrum. Drag to rotate, double-click to reset, choose a color, play/pause, and adjust volume. The layout adapts to mobile.

## Run locally

```sh
cd web
npm ci
npm run dev
```

Open the localhost URL printed by Vite. The page needs a user click to start audio. Pick an audio file supported by the browser or play any of four original synthesized short tracks. No audio is uploaded; no service credentials are needed. Each synthesized WAV is generated in memory (12 seconds, 576,044 bytes), not downloaded.

```sh
npm test
npm run build
```

`dist/` is a standalone static deployment folder. Vite uses relative asset paths so it can be served under a repository subpath. Host over HTTPS for public use; see `DEPLOYMENT.md` for the deliberate GitHub Pages release process.

## Capability boundaries

This release uses amplitude and frequency analysis, not AI inference or learned beat tracking. Singer mode responds to the mixture in 300–3000 Hz and its spectral center, producing smooth multi-axis gestures; it does not isolate a singer or estimate singing pitch. Background music mode responds to 40–300 Hz energy, positive low-frequency changes and mixture level, producing nods and bounce. Switching modes preserves the existing audio source and current pose. It does not run the native application's StemgenRT or BeatNet models and does not separate vocals. It does not capture system audio. Browser WebGL character geometry recreates the native visual cues; it is not SceneKit code running in the browser. The halo is a subtle expanded sphere and the spectrum is shown below the character, not a port of the native mesh silhouette shader.

The native StemgenRT ONNX file is about 37.5 MB; the BeatNet ONNX is about 1.6 MB. A model port would require ONNX Runtime Web, supported operator/state validation, audio feature parity, and device performance measurements. That remains future work. No ONNX/WASM resources are included in the current web bundle.

Playback pauses when the page is hidden to reduce load. Idle rendering occurs only on resize, rotation or color changes; active audio rendering is capped near 30 fps and pixel ratio is capped at 1.5. Replacing an input revokes its object URL. Permanent page teardown releases audio nodes, object URLs, GPU geometry/materials and the renderer. Returning from the back-forward cache leaves the player available but paused.

## Model inspection and deployment footprint

`MODEL_ASSESSMENT.json` records actual ONNX metadata and successful `onnx.checker.check_model` checks, not browser inference results. Both models use IR 8 and standard-domain opset 17.

- StemgenRT: 37,529,132 bytes (35.79 MiB), input stereo `audio_chunk[1,2,128]` plus eight recurrent/history inputs; output four stereo stems and next states. Includes DFT, DynamicQuantizeLinear and MatMulInteger. Its single-file size exceeds a 25 MiB asset limit. A port needs operator support testing, state/feature parity and sustained real-time performance measurements; this build does not load it.
- BeatNet: 1,614,175 bytes (1.54 MiB), inputs `features[1,1,272]`, `hidden[2,1,150]`, `cell[2,1,150]`; outputs three probabilities and next states. Includes Conv and two LSTM nodes. This smaller model is a plausible follow-up for WASM inference, but feature extraction and temporal decoding must be ported and checked before claiming beat tracking. It has not been run in a browser.
- The updated production footprint is recorded after build in `RELEASE.md`. No model or WASM file is shipped. Each 576,044-byte original sample WAV is generated on demand in browser memory.

For an independent local browser regression with installed macOS Chrome (isolated headless session, no existing profile), run `npx tsx tests/browser-smoke.ts` while the dev server is running. Set `MIHO_TEST_URL` to test a static build under `/Miho/`. The test checks WebGL initialization, color selection, audio playback and pause, file replacement, end/replay, mobile overflow and page teardown; screenshots are written to `/tmp`.

## Characters and sample library

Four procedural presets build on the native application's own customization categories: classic sphere with headphones and sunglasses; mint bean with beanie and dot eyes; pink sphere with long bunny ears; purple rounded square with crown and round glasses. Color choices remain available for each preset. Changing a preset disposes the old geometry; shared materials are released during final teardown.

Four 12-second original synthesized arrangements are generated on demand: Little Miho (120 BPM melody), Moonlight Walk / 月光慢步 (80 BPM ambient), Neon Pulse / 霓虹脉冲 (140 BPM electronic percussion), and Synthetic Phrase / 合成唱句 (90 BPM vowel-like harmonic envelopes, not real singing). No third-party recording, commercial song, downloaded music or voice imitation is used. These deterministic sample definitions are part of this project's source. Only the selected track is generated; files are not cached across song switches.
