# 本机音频依赖

| 依赖 | 固定版本／来源 | 许可 |
| --- | --- | --- |
| StemgenRT-5.8 流式 ONNX 图 | stemgen-rt commit `61df8f4aa1555ef110308d01ea92b54ace770979` 的 `model/model.onnx`，teacher004 EMA | [MIT](StemgenRT-LICENSE.txt) |
| ONNX Runtime CPU SDK | Microsoft 官方 `onnxruntime-osx-arm64-1.26.0.tgz` | [MIT](ONNXRuntime-LICENSE.txt)，包内 ThirdPartyNotices 随应用分发 |

模型 SHA-256：`77164d6a581fafb2a31f53fd8ffde44c07cf618472952a4cdba14e68dda3b8b9`。

SDK 压缩包 SHA-256：`7a1280bbb1701ea514f71828765237e7896e0f2e1cd332f1f70dbd5c3e33aca3`。

下载地址保存在 `scripts/prepare-audio-models.sh`。首次构建核对压缩包和模型，运行时再次验证模型；缓存仅在忽略的 `Vendor/` 内，构建脚本把模型、原生库和许可打包到 `.app`。本仓库不提交第三方二进制。

C++ 宿主由 Miho 实现，模型接口、状态顺序和首跳延迟参照 [上游 streaming.py](https://github.com/sweetspotsoundsystem/StemgenRT-5.8/blob/main/stemgenrt/streaming.py)，通过固定输入与该 Python 宿主结果的一致性测试。Python 仅用于开发验证，应用不依赖它。没有复制 JUCE 插件或安装付费分离 SDK。
