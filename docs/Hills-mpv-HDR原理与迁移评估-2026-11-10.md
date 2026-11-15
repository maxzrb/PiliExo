# Hills mpv HDR 原理与 PiliExo 迁移评估

调查日期：2026-11-10，Asia/Shanghai。

## 结论

Hills 1.11.0 的 mpv HDR 显示功能由原生 SurfaceView、gpu-next 渲染器、定制 Android/EGL HDR dataspace 处理共同实现。可以在 PiliExo 独立实现相同技术路线，但必须同时改显示通路和原生 mpv；现有 Flutter Texture 通路只加 mpv 参数不足以完成迁移。

本次通过 ADB 回读已安装 APK、反编译调用层和分析 ARM64 库确认实现。没有启动 Hills 播放内容，没有改变 Hills 设置，没有绕过付费或宿主授权检查，没有将第三方实现复制进应用源码。没有把静态分析当作 Hills HDR 实播、色准、输出位深或性能测量。

## 样本身份

| 项目 | 实际值 |
| --- | --- |
| 本机安装包 | com.mountains.hills |
| 版本 | 1.11.0 / code4139 |
| 架构 | arm64-v8a，split APK |
| base.apk SHA-256 | 42a5b57ab3adca2ae03f3308e9a0e6df0f7c8da236ac3836f2998c24983e3e91 |
| libmpv.so 自报版本 | mpv v0.41.0-dev-g626e5a3b7 |
| libmpv.so SHA-256 | f42cb3bae0eea468d1fe30937dab16bf146ef8cd1e3447a2a7dfe3c04e8642fa |

`adb shell pm path com.mountains.hills` 获取已安装 base / arm64 split 路径，再完整回读。反编译使用本地已有 JADX 1.5.6 CLI；全包反编译有180项错误，因此只引用可直接定位并另行核对的调用和原生证据，不认定整个反编译结果完整正确。

## 第一层：视频直接送到 SurfaceView

APK 中的 `com.mountains.player.mpv.MPVView` 继承混淆后的 `ei.d`，后者直接继承 Android `SurfaceView`，实现 `SurfaceHolder.Callback`。

- Surface 创建、销毁与 JNI attach/detach 联动。
- Surface 尺寸改变时，向 mpv 设置 `android-surface-size=宽x高`。
- 原生 JNI 库为 `libplayer.so`，公开 MPVLib nativeAttachSurface 等接口。
- 播放界面使用原生 MpvPlayerActivity，不能因为应用外壳同样是 Flutter 就认定它通过 Flutter Texture 显示视频。

这与 PiliExo 当前 mpv 输出到 SurfaceTexture、由 Flutter 在普通图层内缩小/合成的路径不同。前一份真机核验已确认 PiliExo 当前的这一行为。

## 第二层：HDR 开关同时改变三个选项

调用层 `mi/j0.java:826–830` 可直接定位到以下关系（这里是参数关系说明，不是移植第三方代码）：

```text
HDR功能有效 → android-hdr-probe=yes
HDR功能有效 → target-colorspace-hint=yes
HDR功能有效 → vo=gpu-next
```

关闭 HDR 时前两项为 no；vo 由独立 gpu-next 设置决定，否则使用 gpu。APK 同时检查其自身会员状态；本次未更改该检查。

`target-colorspace-hint` 是上游 mpv 的颜色空间提示机制；`android-hdr-probe` 则是该二进制包含的定制选项。只复制参数到 PiliExo 现有 libmpv 不会获得相同能力。

## 第三层：定制 Android/EGL 层处理 HDR dataspace

Hills 原生库包含 `ANativeWindow_setBuffersDataSpace` / `ANativeWindow_getBuffersDataSpace` 的引用。ARM64 相关代码和日志支持以下行为：

1. 功能要求 API28+ 且使用 gpu-next，并检查所需 NativeWindow 接口是否可用。
2. 启用前读取并保存 Surface 原 dataspace。
3. HDR 路径请求 `0x09c60000`，即 BT.2020/PQ；相关目标日志字符串为 `bt.2020/pq`。
4. 向 NativeWindow 设置 dataspace 并读回，检查设置是否生效；交换缓冲后也检查是否被驱动改写。
5. SDR 恢复目标为 `bt.709/srgb` / `0x08810000`；设置失败时可退回 SDR，无法恢复时通知核心丢弃 VO。
6. 退出时恢复原 dataspace。

相关原生日志字符串包括：

```text
HDR probe: enabled API=%d EGL RGBA=%d/%d/%d/%d; no HDR metadata
HDR probe: target=%s depth=%d; same EGLSurface
HDR probe: dataspace changed after swap: expected=0x%x read=0x%x
HDR probe: restored original dataspace=0x%x
```

这表明该实现会在保留同一 EGLSurface 的情况下调整输出 dataspace，并与 gpu-next 的目标色彩空间协商配合。它并非只提高屏幕亮度，也并非仅调用窗口 HDR 模式。

原生库另包含 Hills 宿主授权检查，不能作为通用 libmpv 直接替换 PiliExo；本次没有研究或绕过该检查。迁移应从有明确来源的 mpv 构建独立补丁，而不是复用已提取二进制。

## 能力边界

- 读到的主要目标是 BT.2020/PQ，不能直接推广成 HLG、Dolby Vision、HDR Vivid 或 HDR10+ 的所有模式都已验证。
- 日志明确标注 no HDR metadata，不能把该功能等同于完整传送 ST2086、HDR10+ 动态元数据或 Dolby Vision RPU。
- 设置 HDR dataspace 不等于输出已经是10位。必须另测 EGL config、缓冲像素格式、输出精度和渐变色带；本次未实播 Hills，未读取这些运行值。
- 系统进入 HDR 显示模式与亮度提升，不能单独证明像素转换正确或色准达标。
- Hills 的 Dolby Vision Profile5 颜色修正是另一个机制，不能与本次 PQ 输出路径混为一谈。

## PiliExo 的现状与可迁移范围

当前正式 v26.11.9.1 APK 的 libmpv 自报 `mpv v0.41.0-dirty`；二进制字符串中有 gpu-next，但没有 android-hdr-probe，以及上述 NativeWindow dataspace 接口名称。这些字符串只能作为构建差异证据，不能单独证明所有间接实现均不存在。

结合现有源码和上一轮真机链路，迁移至少需要：

| 层次 | 所需改动 | 已有基础 |
| --- | --- | --- |
| Android显示层 | 给 mpv 增加直接显示的原生 SurfaceView，并正确处理创建/销毁、尺寸、切屏、PiP和清屏 | Media3 HDR 的 AndroidView/Hybrid Composition、清屏及生命周期已有实践 |
| mpv原生层 | 独立实现 Android HDR dataspace/颜色空间配对；可先验证公开 EGL 输出选项加 JNI 桥接，必要时才重编译核心 | 正式核心已有 gpu-next/libplacebo 和 rgb10_a2 EGL 配置能力 |
| Dart控制层 | 选择 HDR 输出时绕开普通 VideoController/Flutter Texture；尽量复用现有 mpv 实例和播放控制 | 现有 mpv 音频、倍速、弹幕和洞察逻辑可作为适配基础 |
| 输出验证 | 确认 PQ像素、HDR dataspace、实际位深及失败回退一致 | 现有 ADB SurfaceFlinger/Composer/gfxinfo 采集方法可复用 |

不能只给现有 Texture 标记 HDR，或只设置 Window.colorMode。正确的像素编码、Surface dataspace、输出缓冲格式必须一致；否则可能只是触发 HDR 模式但图像错误。

建议先做可选的“原生 mpv HDR 输出”路径，先覆盖 HDR10/PQ；Media3 保持现有默认/回退功能。不要同时改音频低延迟路线、丢帧策略或倍速恢复。项目已有记录表明擅自更换原生核心曾引起倍速松手卡顿，因此新库必须在固定样例上复验现有音频/倍速行为。

## 后续实现的样例与参考输出（尚未执行）

| 样例输入 | 参考输出或验收条件 |
| --- | --- |
| 固定 HDR10/PQ、10位样本 | 独立活动 SurfaceView，BT2020_PQ类 dataspace；确认实际10位/浮点输出缓冲和正确的PQ目标 |
| 固定 SDR BT.709 样本 | 恢复SDR目标及dataspace，退出HDR模式后画面正常 |
| 同一HDR样本：开关HDR输出 | 明确区分原生HDR与HDR转SDR，不能只比较截图亮度 |
| API不足、dataspace请求失败或交换后被改写 | 有明确日志并安全回退，不以错误HDR标记继续显示SDR像素 |
| 横竖屏、全屏、PiP、后台、切源与退出 | Surface不泄漏、不残留HDR模式、无旧帧覆盖 |
| 既有长按倍速与松手恢复固定样例 | 维持既有音频/进度/丢帧参考行为，无新增卡顿 |

本报告以上记录的是调查阶段。用户随后要求实施，本轮已用独立 JNI 桥接及现有 mpv 核心实现实验路径并开始真机验证，详见 [后续实现记录](mpv原生HDR迁移与P5验证-2026-11-10.md)。验证使用同一应用及固定输入/参考输出，没有制作独立测试应用。

## 原始证据与外部资料

未跟踪的本机目录：`tmp/hills-hdr-20261110/`。其中 `decompiled/sources/mi/j0.java`、`decompiled/sources/ei/d.java`、`decompiled/sources/ei/a.java` 对应参数和Surface；`mpv-hdr-strings.txt`、`native-hdr-refs.txt`、`native-hdr-region.txt` 对应原生库；`piliexo-comparison.json` 对应当前正式库字符串比较。原始 APK /第三方反编译文件不加入应用源码或发布包。

- Android NativeWindow dataspace接口：https://developer.android.com/ndk/reference/group/a-native-window
- Android HDR播放说明：https://developer.android.com/media/grow/hdr-playback
- mpv颜色空间提示参数：https://mpv.io/manual/stable/#options-target-colorspace-hint
- 上游Android/EGL实现对照：https://github.com/mpv-player/mpv/blob/master/video/out/opengl/context_android.c
- Hills官方功能说明：https://hills.im/
