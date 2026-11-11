# mpv HDR 固定样例

本目录采用固定输入和参考输出，验证媒体数据、P5 解码和字幕覆盖层。它不创建独立测试应用。

## 动态元数据与会话交接回归

`dynamic-sei.hex` 每行输入为“名称、PTS、NAL 长度字段字节数、十六进制包”；长度字段为 0 时表示 Annex B。配对参考 `mpv-hdr-dynamic-sei`，覆盖 1～4 字节长度前缀、长度 256 与 Annex B 起始码相似的包，以及损坏尾部不能产生部分回调。FFmpeg HEVC MediaCodec 已有 `hevc_mp4toannexb` 过滤器，生产入口明确使用 Annex B。

```text
python tool/verify_dynamic_hdr_sei.py --cc C:/msys64/ucrt64/bin/gcc.exe --output tmp/dynamic-hdr-regression
flutter test test/plugin/pl_player/mpv_hdr_session_test.dart
```

`session-reuse.json`/`mpv-hdr-session-reuse` 验证画质、尺寸、硬解及编码变更必须重建原生会话；`decoder-options.json`/`mpv-hdr-decoder-options` 验证真实 Dart 控制器将原生返回的 FFmpeg 参数与吞吐参数合并。`vivid-flush.txt`/`mpv-hdr-vivid-flush` 由 `MpvVividFlushTest` 验证 JNI 的空载荷 flush 可清理队列与状态。上述测试不等价于动态 HDR 在设备上已实际激活。

## HDR 信号保留与 EGL 元数据单位

`pq-color-input.txt` 包含 17 个 ST2084 灰阶及 3 个彩色点，覆盖 0–10000 nit；`hlg-color-input.txt` 包含 7 个 HLG 编码点。对应参考 `mpv-hdr-pq-color`、`mpv-hdr-hlg-color` 等于输入编码值，验证颜色映射后仍保留信号。允许每通道 2 个 10 位码值误差，覆盖移动 GPU 的 FP16 舍入。

`hdr-metadata-input.txt` 的 12 列依次为 Rx/Ry/Gx/Gy/Bx/By/Wx/Wy、mastering max/min、MaxCLL、MaxFALL。参考 `mpv-hdr-egl-metadata` 按 EGL 规范乘 50000，覆盖缺失、NaN、非法范围、黑位为零、MaxFALL 大于 MaxCLL 及清空旧元数据；`-1` 为 `EGL_DONT_CARE`。此项直接编译补丁中的 `android_hdr.h`，但不等价于已验证候选 App 的 EGL 提交或 SurfaceFlinger 接收。

固定输入的 SHA256、参考来源及误差限见 `color-samples.json`。示例（Windows NDK，arm64 设备）：

```text
python tool/verify_mpv_hdr_color.py --prefix <候选使用的静态依赖前缀> --mpv-source <已应用本仓库EGL补丁的mpv源码> --ndk <Android-NDK目录> --serial <ADB设备序列号>
```

运行器使用同一份 libplacebo 静态库及无界面的 EGL PBuffer，保存实际输出和 `verification.json` 到 `tmp/mpv-hdr-color-fate/`，退出前移除设备上的命令行运行器。不操作应用界面、不改变系统亮度。另输出旧 460 nit 自动映射策略的数值作为差异证据，不用它更新固定参考。

2026-11-10 MEP-AN00 / API37：PQ 20 点最大误差 0.000606147（约 0.62 个 10 位码值），HLG 7 点最大误差 0.000024，元数据 5 行与参考完全相同。旧策略的 100/203/460/1000 nit 灰阶分别降到约 71.713/128.186/248.799/457.417 nit。这仅证明被测 libplacebo 颜色映射的差异，不是候选 App 与 Media3 的屏幕色准验收。

## MediaCodec 字节格式与界面回归

`mediacodec-hdr-static.hex`、`mediacodec-hdr-static.json` 和参考 `mediacodec-hdr-static-info` 覆盖 7 组 CTA-861.3 Type 1 描述符。参考逐项规定解析后的实际 AVFrame side data、坐标/亮度分母及重复附加时的数量。运行：

```text
python tool/verify_mediacodec_hdr_samples.py --ffmpeg-source <应用FFmpeg补丁后的源码> --prefix <同版本arm64静态依赖前缀> --ndk <Android-NDK目录> --serial <ADB设备序列号>
```

`decoder-modes.json` 配对 `mpv-hdr-decoder-modes`，验证 MediaCodec 没有硬件像素格式提示时仍按实际 `hwdec-current` 显示硬解，初始化期间保留未知状态。

`viewport-scroll.json` 配对 `mpv-hdr-viewport-scroll`，在真实 VideoHeader 中输入“顶部、折叠到评论区、快速回顶、末尾一像素变化”的固定滚动序列。参考要求可见区域变化，而视频布局始终为 400×225、元素保持同一个，避免原生窗口跟随折叠缩小后又放大。它验证 Flutter 布局，不替代手机上的 SurfaceView 动画验收。

```text
flutter test test/plugin/pl_player/mpv_hdr_policy_test.dart
flutter test test/plugin/pl_player/fixed_video_viewport_test.dart
```

## 媒体输入与来源

`dv-p5-five-frames.mp4` 为公开 Jellyfin 测试视频的前5帧，1920×1080、HEVC Main10、Dolby Vision Profile5，时长约0.083秒。保留 dvcC 配置记录、逐帧原始 RPU 和解析后的 Dolby Vision 元数据。源地址、提取命令、字节区间与输入 SHA-256 见 `sample.json`。

`-strict unofficial` 用于保留 MP4 中的 Dolby Vision 配置记录；省略后 FFmpeg 可能仅保留 RPU 而不写 dvcC，不能用作本例的等价输入。

## FATE 风格参考输出

参考结果保存在 `test/ref/fate/`：

- `mpv-hdr-dv-p5-metadata`：容器 Profile5、无 HDR10 兼容基层、5帧均保留 RPU 和结构化元数据。
- `mpv-hdr-dv-p5-framemd5`：软件解码前5帧的确定性10位 YUV 校验和。
- `mpv-hdr-dv-p5-rgb.json`：经 FFmpeg/libplacebo 执行 Dolby Vision 修正并转换到 SDR BT.709 后，首帧选定位置的 RGB 参考值。允许每通道3级误差，避免不同 GPU 的小幅舍入差异。

运行：

```text
python tool/verify_mpv_hdr_samples.py
python tool/verify_mpv_hdr_samples.py --libplacebo
python tool/verify_mpv_hdr_samples.py --libplacebo --loop-output tmp/mpv-hdr-fate/dv-p5-loop.mp4
```

后者要求 FFmpeg 启用 libplacebo 和 Vulkan。失败时输出参考与实际值的差异，退出码为1；实际文本保存到 `tmp/mpv-hdr-fate/`。

参考由本机 FFmpeg `git-2026-10-14-045dea2a34` 生成并复跑核对。RGB 参考是桌面渲染基准，不能替代 Android 候选包的 PQ 输出、实际位深、显示色准或原生图层验收。

真机覆盖层回归另使用短样本的无损10秒循环版本：重复600次，输出602帧、10.033秒，仍保留 dvcC、Profile5 和逐帧 RPU。该文件只用于确认短片段不会持续出现加载遮罩，以及字幕、弹幕和控制层合成；它不能代表真实长片的解码性能。循环文件属于临时验收输入，不提交到固定参考。

## 字幕和控制层

`overlay.vtt` 给出双行字幕、下一条字幕和清空时序的输入。Flutter 组件测试使用对应文本检查更新、隐藏、拖动位置，以及字幕、弹幕文本和控制按钮同时存在时的响应。原生 Surface 与 Flutter 覆盖层的实际合成顺序仍须在设备上验证。

2026-11-10 已在 MEP-AN00 / Android API37 上通过正式应用入口加载 `overlay-device.srt`。原生输出日志同时确认 `Profile5`、`hwdec=no`、`dolbyvision`、`gpu-next`、参数43和BT2020_PQ；截图确认双行字幕、滚动弹幕、进度条、暂停按钮在全屏及竖屏返回后均正常显示，暂停操作把媒体会话切为 `PAUSED`。

```text
flutter test test/plugin/pl_player/mpv_hdr_policy_test.dart
flutter test test/plugin/pl_player/mpv_hdr_subtitle_test.dart
```
