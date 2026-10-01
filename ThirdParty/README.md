# 本机音频依赖与致谢

| 依赖 | 固定版本／来源 | 许可 |
| --- | --- | --- |
| BeatNet CRNN 模型与导出架构 | Mojtaba Heydari，commit `81cedd4beeb7235262db80969a0c9ce9a48a0ed4`，`src/BeatNet/models/model_2_weights.pt` | [CC BY 4.0](BeatNet-LICENSE.txt) |
| StemgenRT-5.8 流式 ONNX 图 | stemgen-rt commit `61df8f4aa1555ef110308d01ea92b54ace770979` 的 `model/model.onnx`，teacher004 EMA | [MIT](StemgenRT-LICENSE.txt) |
| ONNX Runtime CPU SDK | Microsoft 官方 `onnxruntime-osx-arm64-1.26.0.tgz` | [MIT](ONNXRuntime-LICENSE.txt)，包内 ThirdPartyNotices 随应用分发 |
| madmom 特征约定 | [CPJKU/madmom](https://github.com/CPJKU/madmom)：对数频率滤波器、Hann FFT、正谱差分 | [BSD 3-Clause](Madmom-LICENSE.txt)，未使用或分发 madmom 的预训练模型 |

**BeatNet Attribution:** Mojtaba Heydari, Frank Cwitkowitz, Zhiyao Duan, *BeatNet: CRNN and Particle Filtering for Online Joint Beat Downbeat and Meter Tracking*, ISMIR 2021. [Original project](https://github.com/mjhydri/BeatNet), [paper](https://arxiv.org/abs/2108.03576), [CC BY 4.0 license](https://creativecommons.org/licenses/by/4.0/).

Miho modifications: converted the original model-2 checkpoint to a state-explicit, single-frame ONNX graph with `scripts/export-beat-model.py`. Reimplemented native causal features, ONNX hosting and tempo/phase decoding. Miho does **not** distribute or run the original particle filter. Changes and attribution accompany the graph, sources and app; no author endorsement is implied.

校验和（SHA-256）：

- BeatNet 上游 model-2 checkpoint：`5878a18c079fa0b0139879b14ed2b5b7595faef8c3d16210aed141fd00fa2d58`。
- 本项目转换的 BeatNet ONNX：`9f17e72c12ffda524b042e55f3a1ad1e81acddd1baaf3c0440d7544437f8fe3e`。
- StemgenRT 模型：`77164d6a581fafb2a31f53fd8ffde44c07cf618472952a4cdba14e68dda3b8b9`。
- SDK 压缩包：`7a1280bbb1701ea514f71828765237e7896e0f2e1cd332f1f70dbd5c3e33aca3`。

BeatNet 的 1.6 MB 转换图提交在 `Resources/Models/beatnet.onnx`。大的分离模型和原生 SDK 下载地址保存在 `scripts/prepare-audio-models.sh`，只缓存在忽略的 `Vendor/` 内。构建脚本把模型、运行库、本文及许可打包到 `.app`。运行时核对两份模型的校验和。

BeatNet 导出与特征验证使用 Python/PyTorch；应用不依赖 Python。原始与转换模型的连续状态输出、136 个滤波器和原生 FFT 特征均有独立数值一致性验证。分离宿主另与 [上游 streaming.py](https://github.com/sweetspotsoundsystem/StemgenRT-5.8/blob/main/stemgenrt/streaming.py) 固定输入结果核对。
