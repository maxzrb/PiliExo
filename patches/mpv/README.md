# Android mpv 本地构建说明

本目录保存播放器原生改动及对应上游源码版本。正式 APK 使用本机交叉编译的 mpv，不依赖 GitHub Actions。

`sources.json` 记录各组件的仓库、标签、源码归档 SHA-256 和长度。mpv 基线为 v0.41.0；依次应用 `mpv-lavc-java-vm.patch` 和 `audiotrack-low-latency-experiment.patch`。前者保留 media-kit 的 Java VM 入口，后者为 AudioTrack 添加默认关闭的低延迟与采样率适配选项。原生库仍须导出原有 55 个 `mpv_*` API。

本轮工具链为 Windows NDK 28.2.13676358、API 24、CMake 3.22.1、Meson 1.11.2、Ninja 1.13.2。分别使用 `aarch64-linux-android24-clang` 和 `armv7a-linux-androideabi24-clang`，依赖静态链接；C++ 使用 `c++_static` 与 `c++abi`，禁止把主机 RPATH 或主机 DLL 带进 Android 库。共享库链接要求 `--no-undefined` 和 `-z,max-page-size=16384`。mpv 启用 libmpv、AAudio、OpenSL ES、AudioTrack、Android 硬解，禁用 cplayer、GPL、Lua、Vulkan 与文档生成。32 位 FFmpeg 使用 ARMv7/NEON，两个架构分别安装到独立前缀，禁止共用编译产物。

正式构建必须先运行 `lib/scripts/build.ps1` 生成当前提交的版本元数据，再同时传入 `PILI_AUDIO_TRACK_CANDIDATE=true`。此开关必须与本目录补丁构建的原生库成对使用；原始 media-kit 库不识别新增 AudioTrack 选项。应用不全局指定 `audio-samplerate`：普通单双声道 PCM 按设备能力申请低延迟，高于 48 kHz 的 PCM 和直通音频保留原请求并避开小缓冲路径。申请采样率不等于证明设备 DAC 原样输出。

本地生成常规 Release APK 后，使用 `lib/scripts/package_android_native.py` 分别替换同架构 `libmpv.so`，清理其他 ABI，执行 16 KB zipalign 并使用原正式证书签名。该脚本要求提供预期原生库 SHA-256，校验 ELF 架构、包内其他文件不变、原生库字节一致及签名前后证书一致。发布前还必须核验安装包版本、Dart 元数据、FFmpeg/JNI 注册、原生依赖、导出表和设备覆盖安装。

原生策略回归可运行 `python -m unittest discover -s test/native`，需要 PATH 中有 C 编译器。它从实际补丁提取采样率与快速路径函数，覆盖 44.1/48/96/192 kHz、直通、多声道与无效设备采样率。真机听感和物理高采样率输出仍需独立复核。

AAudio 另有明确约束：保留原 MMAP 可用路径，不用分配音效会话、软件增益或全局重采样补偿响度。2026-10-18 的会话混音实验已被用户否决，相关改动不得纳入本目录正式补丁。
