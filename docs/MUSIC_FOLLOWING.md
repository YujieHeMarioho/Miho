# 节拍跟踪与自然律动

2026-10-01，v0.6.0。前版的人声分离能支持长音保持，但缺少可靠的音乐拍子；持续说唱还会被错误地当作长音，因此不能用它的自动测试通过来证明快歌观感合格。

## 实际接入

- [BeatNet](https://github.com/mjhydri/BeatNet)：实际使用预训练 CRNN，转换为显式传入／传出两层 LSTM 状态的 ONNX 图，在 Mac 原生 CPU 上运行。每 20 ms 输入 272 维特征，输出普通拍、强拍和非拍概率。保留训练时 1411 点 Hann FFT、136 个对数频率滤波器和正谱差分，使用过去的 64 ms 音频，无未来采样。
- Miho 的因果解码器：用最多 8 秒的**标量概率**估计周期和相位；结合自相关与拍点的圆周一致性，避免只看相关性导致总选半速。相位继续前进，检测结果平滑校正，节奏变化需要持续证据。它是本项目实现，不声称运行了上游粒子滤波器。
- [StemgenRT-5.8](https://github.com/sweetspotsoundsystem/StemgenRT-5.8)：保留原有真实人声／鼓点分离模型，唱腔、力度和重音仍来自独立声音。持续的人声存在不再自动压掉节拍律动。
- `Choreographer`：每拍点头，连续的身体起伏和每两拍左右换重心。高速时身体起伏可取半速，但点头继续标记跟踪到的每一拍。躯干、墨镜、耳机和耳朵共享一个拍子，幅度与音量、鼓声及人声相关。唱腔延展叠加到姿态上；没有定时轮换舞步片段。

这里的“跟踪到的拍子”可能与乐谱的半速／倍速读法不同。模型不是歌词理解、歌手身份识别或完整人体 AI 编舞。

## 行为研究如何用于角色

[Visual tuning and metrical perception of realistic point-light dance movements](https://www.nature.com/articles/srep22774) 使用身体的拍级弹动和更慢的侧向动作研究舞蹈节律。[Keeping the Beat](https://pmc.ncbi.nlm.nih.gov/articles/PMC4966945/) 比较随音乐弹动和鼓掌的同步行为。[现场音乐实验](https://pubmed.ncbi.nlm.nih.gov/36347227/) 发现低频声音影响观众运动。

由这些研究得到的设计判断是：给所有主要部件稳定、共享的节拍；慢一些换重心；低频和重音改变力度。球形角色没有人体膝、髋、肩的完整骨架，因此以身体位移、俯仰和转动表达这些关系。这是设计应用，不能宣称完全复制真人舞者动作。

惯性滤波会带来相位滞后。目标轨迹按滤波器响应提前，并检查**最终姿态**是否落在拍点上；限制速度和加速度，防止碎拍重置身体产生抽搐。相位重新校正时连续衔接。

## 其他模型的取舍

| 项目 | 能力 | 本次用途 |
| --- | --- | --- |
| [Beat This!](https://github.com/CPJKU/beat_this) | Transformer 拍点／强拍识别 | 调研；没有作为持续低延迟原生输入模型接入 |
| [BEAST](https://github.com/WildHoneyPie/BEAST) | 在线节拍／强拍识别研究 | 调研；当前选择可固定下载、可转换和可验证的 BeatNet 权重 |
| [DiscoForcing](https://github.com/CurMack/DiscoForcing) | 因果全身音乐舞蹈生成 | 调研；公开演示使用 GPU 特征／模型、6 秒特征窗和显示缓冲，当前没有移植到原生 Mac 球形角色 |
| [EDGE](https://github.com/Stanford-TML/EDGE)、[LODGE](https://github.com/li-ronghui/LODGE) | 完整人体音乐舞蹈生成 | 调研；没有下载或运行它们的舞蹈模型 |

本次真正运用的是 BeatNet 节拍模型和 StemgenRT 分离模型，动作由上述连续控制实现。没有把调研过的项目列成已集成功能。

## 验证边界

测试分为独立模型／特征一致性、节拍解码、最终姿态对拍、速度与加速度限制、音乐样例文件和真实播放器。模型路径正常、合成信号测试通过，不能代替用户对真实歌曲的观感验收。最新结果和未完成项见 [VALIDATION.md](VALIDATION.md)。
