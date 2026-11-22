# Android mpv 本地构建说明

本目录保存播放器原生改动及对应上游源码版本。正式 APK 使用本机交叉编译的 mpv，不依赖 GitHub Actions。

`sources.json` 记录各组件的仓库、标签、源码归档 SHA-256、长度及正式补丁顺序。mpv 基线为 v0.41.0。AudioTrack 小缓冲实验补丁单独保留。原生库须导出原有 55 个 `mpv_*` API。

FFmpeg 的动态 HDR、运行中吞吐提示和解码前丢帧共用
`ffmpeg-android-dynamic-hdr.patch`。mpv 在播放倍率变化时把源帧率乘以目标倍率提交给解码线程。
Java MediaCodec 接收限在 15–240 的 `operating-rate` 提示，驱动拒绝时继续使用现有解码器。
实际跟不上音频时，FFmpeg 每 500ms 根据成功解码的输出数估算吞吐，按
`1 - 实测吞吐 / 目标吞吐` 累计丢帧额度。仅在额度足够时省去完整的 H.264/HEVC 非参考访问单元。
关键帧、参数集、带新 extradata 的包、含参考画面或无法确认依赖关系的包均保留。
1 倍时不使用该预算。目标倍率改变或发生跳转时清空旧预算。

本轮工具链为 Windows NDK 28.2.13676358、API 24、CMake 3.22.1、Meson 1.11.2、Ninja 1.13.2。分别使用 `aarch64-linux-android24-clang` 和 `armv7a-linux-androideabi24-clang`，依赖静态链接；C++ 使用 `c++_static` 与 `c++abi`，禁止把主机 RPATH 或主机 DLL 带进 Android 库。共享库链接要求 `--no-undefined` 和 `-z,max-page-size=16384`。mpv 启用 libmpv、AAudio、OpenSL ES、AudioTrack、Android 硬解，禁用 cplayer、GPL、Lua、Vulkan 与文档生成。32 位 FFmpeg 使用 ARMv7/NEON，两个架构分别安装到独立前缀，禁止共用编译产物。

构建必须先运行 `lib/scripts/build.ps1` 生成当前提交的版本元数据。注意：2026-10-18 长按 exact 已通过手测的 22:12 包实际使用原 libmpv（SHA256 `e03d7145209d82791048674bd07cd95ce88115dd7cb77524b63bdf0ddf44ae98`），AOT 未启用 AudioTrack 候选参数。后续洞察清理包擅自换成下述定制库并启用候选配置后，用户反馈松手持续卡顿复发，因此当前恢复该已验证组合。不能仅以本目录原生策略单测通过为由再次替换现有播放核心。下述适配策略及 `d822d86b…` 定制库仅保留为历史正式包/原生研究记录，不作为当前 exact 手测路线默认。若另行启用新增选项，必须与本目录补丁构建的原生库配套；原始库不识别这些选项。应用不全局指定 `audio-samplerate`：普通单双声道 PCM 按设备能力申请低延迟，高于 48 kHz 的 PCM 和直通音频保留原请求并避开小缓冲路径。申请采样率不等于证明设备 DAC 原样输出。

本地生成常规 Release APK 后，使用 `lib/scripts/package_android_native.py` 分别替换同架构 `libmpv.so`，清理其他 ABI，执行 16 KB zipalign 并使用原正式证书签名。该脚本要求提供预期原生库 SHA-256，校验 ELF 架构、包内其他文件不变、原生库字节一致及签名前后证书一致。发布前还必须核验安装包版本、Dart 元数据、FFmpeg/JNI 注册、原生依赖、导出表和设备覆盖安装。

原生策略回归可运行 `python -m unittest discover -s test/native`，需要 PATH 中有 C 编译器。它从实际补丁提取采样率与快速路径函数，覆盖 44.1/48/96/192 kHz、直通、多声道与无效设备采样率。真机听感和物理高采样率输出仍需独立复核。

AAudio 另有明确约束：保留原 MMAP 可用路径，不用分配音效会话、软件增益或全局重采样补偿响度。2026-10-18 的会话混音实验已被用户否决，相关改动不得纳入本目录正式补丁。
# mpv Android 补丁

## `android-egl-bt2020-pq.patch`

面向 mpv `v0.41.0`。增加默认关闭的 `android-hdr-signal-passthrough` 选项；启用后，PQ 使用 BT.2020/PQ EGLSurface，HLG 在视频重配置阶段切换为 BT.2020/HLG EGLSurface，并保留 HLG 传递函数及 1000 nit 参考条件。普通 SDR 路径不启用该选项。

应用侧使用 PQ `target-peak=10000`、`tone-mapping=clip`、`gamut-mapping-mode=clip`、`hdr-compute-peak=no`，让 Android 适配面板亮度。不能把 `desiredMaxLuminance` 当成这里的目标峰值，否则先在 mpv 压缩、再被系统映射。10000 是 PQ 信号上限，不表示面板亮度。HLG 不套用这个上限。

每次交换缓冲前，补丁将仍适用于 PQ 输出的原始 mastering/MaxCLL/MaxFALL 通过 `EGL_EXT_surface_SMPTE2086_metadata` 和 `EGL_EXT_surface_CTA861_3_metadata` 提交并查询核对。按 EGL 规范统一乘 50000；未知字段保留未知，切到 HLG 或缺失元数据时清除旧值。没有发送 Dolby Vision RPU、HDR10+ 或 HDR Vivid 动态元数据。缺失扩展会在日志中显示；驱动拒绝元数据会记录警告，不能仅凭 dataspace 声称与 Media3 一致。

EGL 色彩空间缺失或创建失败时让 VO 初始化失败，应用回退 Media3。旧核心不识别新选项时也回退；不再以旧补丁或 dataspace-only 路径冒充这版实现。JNI 同时核对实际 10 位/浮点格式、目标 PQ/HLG 和相应 NativeWindow dataspace。

固定输入与参考输出见 `test/fixtures/mpv_hdr/color-samples.json`、`test/ref/fate/mpv-hdr-*-color` 和 `mpv-hdr-egl-metadata`。`tool/verify_mpv_hdr_color.py` 用候选的同一份 libplacebo 静态库构建命令行 FATE 运行器，在 Android 离屏 EGL 上回读数值，不创建独立测试 App。参考由 ST2084 公式、恒等 HLG 输入和手算 EGL 单位生成，不从候选输出生成。具体运行参数见固定样例 README。

## `ffmpeg-mediacodec-hdr-static-info.patch`

面向 `sources.json` 中的 FFmpeg 基线。MediaCodec 硬件缓冲不经过 `ff_get_buffer`，因此在包装硬件帧时补调标准 `ff_decode_frame_props`，传递容器 coded/decoded side data 中的 mastering/CLL 等属性；硬件时间戳随后仍使用 MediaCodec 输出时间戳。另将输出 MediaFormat 中可用的 `hdr-static-info` 转为 AVFrame side data，保留已有属性。

Android 的 Type 1 描述符必须为 25 字节、ID 为 0；按小端读取。色度坐标单位为 1/50000，mastering 最大亮度和 CLL/FALL 为 1 nit，最小亮度为 1/10000 nit。不能直接套用 EGL 的 50000 倍亮度表示。无数据、零值未知字段、错误长度或不支持的描述符不会被伪造成完整 HDR 信息。

`test/fixtures/mpv_hdr/mediacodec-hdr-static.hex` 和 `test/ref/fate/mediacodec-hdr-static-info` 为 7 组固定输入/独立参考。运行 `tool/verify_mediacodec_hdr_samples.py`，直接编译本补丁中的解析函数并使用相同 libavutil 分配实际帧 side data；不启动测试 App。解析样例通过不等于所有厂商 MediaCodec 都会提供这些数据，必须另核对最终 SurfaceFlinger 的 HDR metadata types。

## `mpv-android-late-output-drop.patch`

`mpv-android-late-output-drop.patch` 为 `mediacodec_embed` 保留按音频 PTS 判断的解码前丢帧请求。持按期间已解码画面走常规送显，解码负载由 FFmpeg 的非参考访问单元预算控制。

回到较低的基础倍速时进入 250ms 过渡，每次呈现前最多跳过一张确认过期的画面，暂停新的解码前丢帧请求。相邻提交时间至少隔开基础倍率帧间隔的九成，原有较晚的呈现时刻仍保留。音画差未达丢帧阈值或后继帧尚未到期时保留当前画面。重新加速、暂停或跳转会清除过渡状态。

普通纹理输出也跟踪复速并重新累计显示同步误差。复速最初 250ms 暂缓 VO 的超时丢帧和音画纠偏重复帧，音画差回到 50ms 内或保护满 3 秒时恢复正常策略。处于保护期的画面继续按基础倍率调度。

Android mpv 在线分轨点播独立读音频，避免视频积压占满共享的解封装队列。倍速及短暂追帧窗口中，实际声卡欠载时保留最后一帧，等原有音频输出恢复后继续同步。固定输入与参考输出见 `test/fixtures/mpv_frame_drop_policy/` 和 `test/ref/fate/mpv-late-output-drop`。

`mpv-android-audio-clock.patch` 按已排队 PCM 各段原有的处理倍率计算媒体时长，供音频 PTS 和视频调度使用。AudioTrack 按完整采样帧上报设备容量，应用为 AudioTrack 首选输出配置 100ms 软件缓冲，设备容量更大时沿用设备下限。混合倍速时钟和均匀丢帧的固定输入与参考输出通过 `python -m unittest discover -s test/native` 比较。

## 2026-11-10 direct-fixed 候选范围

普通 HDR 且硬解开启时使用 mpv `mediacodec_embed` + `mediacodec`，由解码器直接输出到原生 Surface；P5 或关闭硬解时保留 `gpu-next` 路径。直出绕过 mpv shader，界面隐藏不适用的超分控制，保存的偏好不改。

早期 direct-fixed 核心仅应用 JavaVM 兼容与 EGL HDR 补丁；正式动态 HDR 核心还需要 FFmpeg 的 `ffmpeg-android-dynamic-hdr.patch`。上述静态元数据补丁保留为研究及解析 FATE 样例：输出格式补偿、容器属性补偿两轮真机 GPU 硬解均仍为 metadata types=0，因此没有纳入正式核心。`sources.json` 的 `patches` 和 `researchPatches` 区分正式补丁与研究补丁。

首个 direct 候选因本地 NativeWindow dataspace=UNKNOWN 被误判失败并回退 Media3。修正版不再把 GPU 窗口的查询条件套到 MediaCodec：检查实际 VO/硬解/源 PQ 或 HLG，诊断标为 decoder-managed，最终缓冲色彩标记独立核对 SurfaceFlinger。GPU 路径仍严格检查位深、传递函数与 dataspace。

## 动态 HDR 源码准备与参数传递

先按 `sources.json` 的归档 SHA-256、长度和版本准备源码，再运行以下命令。工具校验清单中全部补丁的 SHA-256，只按 `patches` 顺序应用正式补丁；已应用的补丁会检查并跳过，不会自动应用 `researchPatches`。

```text
python tool/prepare_mpv_sources.py --mpv-source <mpv源码目录> --ffmpeg-source <FFmpeg源码目录>
python tool/prepare_mpv_sources.py --mpv-source <mpv源码目录> --ffmpeg-source <FFmpeg源码目录> --check
```

`piliexo_dolbyvision`、`piliexo_metadata_callback`、`piliexo_metadata_opaque` 属于 FFmpeg MediaCodec 解码器私有选项。JNI 返回本会话的解码参数，由 Dart 在每次打开媒体时与 `operating_rate` 合并到 `vd-lavc-o`，不能作为 mpv 顶层选项设置。回调使用递增令牌，释放时从注册表移除并等待正在执行的 JNI 调用结束；迟到回调不再访问已释放的对象。

FFmpeg HEVC MediaCodec 的 `hevc_mp4toannexb` 位流过滤器保证送入解码器的是 Annex B，因此补丁明确传入 `nal_length_size=0`。独立解析调用需要明确给出 1～4 字节长度前缀，禁止按 `00 00 01` 猜测输入格式。

本轮修改了 FFmpeg 内嵌解析头，必须重新准备并编译双 ABI 核心，再与当前 Dart/Kotlin/JNI 一起构建。不得把旧正式核心和新源码混包后宣称全部修复已进入 APK；源码修复和设备实播验收分别记录。
