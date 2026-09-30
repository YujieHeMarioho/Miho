# Miho 迷糊 🎧

一个会随电脑声音跳舞的 **3D macOS 桌面精灵**。为 **Tencent Music Hackathon（腾讯音乐黑客松）**制作。

<p>
  <img src="docs/images/miho-idle.png" width="230" alt="蓝色毛团、棕色耳机和黑色墨镜的 3D Miho" />
  <img src="docs/images/miho-dancing.png" width="230" alt="Miho 的耳朵 Wave" />
</p>

这一分支是 `feat/miho-3d-dance`，原来的基础版保留在 `main`。新版根据用户提供的 Miho 参考图重建：蓝色椭圆毛团、两只短耳朵、棕色弧形耳机和黑色梯形墨镜。身体体积、短绒、镜框厚度与耳机均由本机 3D 几何渲染。身体、双耳、耳机和墨镜分别参与错开的动作。

<img src="docs/images/miho-dance-preview.gif" width="300" alt="六种舞步的连续 3D 动画预览" />

## 新版体验

- **六种舞步**：左右摇摆、软糖波浪、耳朵 Wave、重拍点头、滑步转身、开心弹跳。每八个估计节拍换一组动作，打乱组合并避免相邻重复，约 0.38 秒平滑过渡。
- **跟随声音**：音量控制动作力度，真实瞬态添加重拍；低频与音色影响舞步组合。音乐软件、Chrome 视频、本地音频和多个应用的混合声音都走同一条系统输出捕获链路。
- **三种状态**：轻柔陪伴、松弛律动、活力满满。状态变化有平滑与延迟确认，避免每帧闪变。
- **待机也有生命感**：呼吸和轻轻晃动，随机探头、歪身、单耳抖动，耳机和墨镜略微滞后；停止声音后约一秒回到待机。每次启动都有不同的微动作节奏。
- **舞步预览**：从右键／菜单栏打开，自动轮换或点选舞步，比较三种动作力度。预览不需要音频权限，不影响桌面角色的真实声音输入。

这里的“情绪”是依据声音特征得到的动作状态，**不是对歌词、歌曲含义或真实情感的识别**。无需歌名、服务器、外部 API 或模型下载。

## 使用

需要 **macOS 14.2 或更新版本**。当前脚本生成本机架构的应用，已在 Apple Silicon Mac 上运行验证。

```bash
./scripts/build-app.sh
open dist/Miho.app
```

构建需要 Xcode 与 Swift 5.10 或更新版本。脚本优先使用 `/Applications/Xcode.app`，不改变全局 `xcode-select`；其他位置通过 `DEVELOPER_DIR` 指定。构建好的应用位于 `dist/Miho.app`，二进制不提交到 Git。

1. 首次启动点击「开始听音乐」，允许系统音频捕获。
2. 播放音乐或视频，Miho 开始跳舞；暂停播放后回到待机。
3. **拖动** Miho 换位置，下次启动会记住位置。
4. 点击菜单栏的笑脸或**右键**角色，调整灵敏度、暂停律动、隐藏／显示或退出。
5. 选择「**舞步预览…**」查看不同动作；隐藏后再次打开应用，也会让 Miho 回到桌面。

蓝色身体约 140 点宽，含耳机的人物约 200 点宽、高；透明窗口为 220 × 260 点，留出摆动和弹跳的活动空间。窗口不占 Dock，不抢键盘焦点，显示在普通窗口上方，并跟随桌面空间。

## 音频权限与隐私

Miho 使用 Apple **Core Audio Process Tap** 分析系统输出，只接收声音 Tap，不加入硬件麦克风输入。应用不请求麦克风权限，不录制屏幕，不保存或上传音频，也不连接服务器。

权限入口：系统设置 → 隐私与安全性 → **屏幕与系统音频录制** → **仅系统音频录制** → Miho。不同 macOS 版本名称可能稍有区别。

- 没有声音时，Core Audio 可以等待第一个播放源，精灵仍正常待机。
- 正在播放却没反应：检查权限，从 Miho 菜单选择「重试音频连接」。
- 设备切换和唤醒会触发延迟合并后的重连；暂停期间不会自动重新捕获。
- 本地临时签名随重新构建可能需要重新授权。跨电脑分发的 Developer ID 签名与公证尚未加入。

## 开发与测试

```bash
./scripts/test.sh
./scripts/build-app.sh
```

开发调试使用 `CONFIGURATION=debug ./scripts/build-app.sh`。先退出正在运行的 Miho，再启动新构建。

菜单中的「关于 Miho 与连接状态」显示捕获状态、音频回调、鼓点与捕获帧到动作状态的时间。关闭其他 Miho 实例后，可运行十秒诊断：

```bash
./dist/Miho.app/Contents/MacOS/Miho --probe
```

诊断期间需要允许音频捕获并播放声音；只输出标量统计。其他入口：

```bash
# 打开连接状态 / 舞步预览窗口
./dist/Miho.app/Contents/MacOS/Miho --diagnostics
./dist/Miho.app/Contents/MacOS/Miho --dance-studio

# 从同一个 3D 场景导出预览、舞步图与图标；不启动音频捕获
./dist/Miho.app/Contents/MacOS/Miho --export-artifacts dist/artwork
./dist/Miho.app/Contents/MacOS/Miho --export-motion dist/artwork/miho-dance-preview.gif
```

不要在已有实例运行时用普通启动／诊断命令创建多个捕获实例。绘图导出命令执行后会直接退出。

### 结构

- `MihoCore/RhythmAnalyzer`：512 样本窗口的音量、低频、明亮度近似值和瞬态检测；自适应阈值、冷却与平滑。
- `MihoCore/Choreographer`：连续律动时钟、合理鼓点间隔跟随、八拍组合洗牌、动作混合、随机微动作与状态防抖；不依赖 UI。
- `MihoDesktop/CharacterScene`：持久化 3D 场景，独立的双耳和配件、物理材质、柔和灯光和透明地面阴影。`FurGeometry` 生成短绒网格。
- `MihoDesktop`：私有音频 Tap、后台生命周期、30 Hz 姿态计算、最高 60 Hz SceneKit 动画、SwiftUI 控件、桌面面板和菜单栏。姿态更新独立于设置和诊断 UI，避免后者每帧重排。
- `Miho`：应用入口；打包脚本生成图标、权限说明和本地签名。

数据流：**系统输出 → 音频 Tap → 音量／音色／瞬态 → 舞步编排 → 3D 身体、双耳与配件**。音频线程与 UI 之间只传递标量快照；不保存 PCM。图标、预览图、GIF 和桌面角色使用相同的几何与动作定义。

SceneKit 的帧率设置是目标值，实际由显示器和设备决定；导出使用 Apple 的 [SCNRenderer 快照接口](https://developer.apple.com/documentation/scenekit/scnrenderer/snapshot%28attime%3Awith%3Aantialiasingmode%3A%29)。

## 当前边界

本版聚焦一个角色的本机 3D 形象、连续舞步与音色反应。暂不加入手机灵动岛、角色商店、歌曲识别或 AI 编舞。节奏时钟用于舞步连续性，不承诺精确 BPM 或所有歌曲的拍点准确率。人声与通知声也会驱动动作。

系统静音不一定让应用输出流变成零；让 Miho 休息可暂停播放或从 Miho 菜单暂停。受内容保护或系统限制的音频不保证可以捕获。不同耳机和音频路由的兼容性仍需扩展设备验证。

目标为低于 150 ms 的声音响应。内置诊断测量捕获帧到动作状态，**不含 3D 插值、显示扫描和完整播放端到画面端延迟**。当前验证记录见 [docs/VALIDATION.md](docs/VALIDATION.md)。开发按里程碑提交到 Git，可分别回滚形象与动作改动。
