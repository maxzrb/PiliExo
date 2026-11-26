# mpv 与 FFmpeg Android 升级流程

本文记录 PiliExo 本轮从 mpv 0.41.0 升级到 0.42.0，并把 FFmpeg 从 n9.0.1
升级到 2026-11-25 的 Git `master` 快照。目标是让下一次升级可以在干净环境复现，
并在编译、静态检查和真机播放之间建立明确边界。

## 当前基线

| 组件 | 版本 | 归档字节数 | SHA-256 |
| --- | --- | ---: | --- |
| Flutter | 3.47.9 | - | - |
| Android NDK | 28.2.13676358 | - | - |
| Android API | 24 | - | - |
| mpv | v0.42.0 | 7,515,468 | `bcfebbfa2b65a6d88dc97ea18117831072373e38b5785a2afb874ed4df5070dd` |
| FFmpeg | 9.1.git，`master@bf11bea4` | 18,341,856 | `261b6ea5c174b286598b4e9c1a88bbb0e87b73a392730bafb3565bf0f2cdf50d` |
| mbedTLS | v3.6.5 | 5,672,091 | `b7cbbfb717f0c38521192d7954a2eb6b7ada5a10a44f72dadbae6655e7300023` |
| fribidi | v1.0.16 | 2,144,176 | `5a1d187a33daa58fcee2ad77f0eb9d136dd6fa4096239199ba31e850d397e8a8` |
| dav1d | 1.5.4 | 1,748,189 | `a1d5b63d2d38ec9bd03acf643caa51fa22edd1e89c5a109c4807717216bbec07` |
| FreeType | VER-2-14-3 | 2,515,533 | `dc49de6b01a266eef4876a4dd34d9842c475d3e28ff2eff63bd2fb760ab56261` |
| libwebp | v1.6.0 | 3,833,512 | `93a852c2b3efafee3723efd4636de855b46f9fe1efddd607e1f42f60fc8f2136` |
| libass | 0.17.5 | 351,516 | `fa286fc9ee1ba3b932703a3df7b8474d01dc8abe29ec69b6fa68781dc4bf7acc` |
| libplacebo | v7.387.0 | 972,798 | `f9e62d3774a9c4cfd198ec3abaa88294aaade2e31c04d5ab02bcf4abc98b1df5` |
| HarfBuzz | 14.3.1 | 37,889,473 | `05e602daf0846d7497d842807766ea32ca270f3e2c9284ce03811a2a1ed669c9` |

完整清单以 [sources.json](../patches/mpv/sources.json) 为准。

FFmpeg 可以作为独立组件滚动升级，mpv 源码不必随每次 FFmpeg 提交同步改动。当前
APK 中的 FFmpeg 是静态库，最终全部进入 `libmpv.so`，因此不能只替换 `.a` 文件，
必须重新构建 FFmpeg 静态库并重新链接 `libmpv.so`。只有 mpv 0.42 仍能通过当前
FFmpeg 头文件编译、最终链接和静态门禁时，才可把这次跨组件升级视为独立完成。

Git `master` 是移动目标。正式清单必须同时记录分支名、完整提交 SHA、归档长度和
SHA-256，实际构建只使用该提交。不能把“今天最新的 master”本身当作可复现版本。

正式发布同时构建 arm64 和 ARMv7。32 位构建使用独立的 FFmpeg 源码树、配置、
依赖前缀和 Meson 构建目录，避免混入 arm64 的 `.a` 或生成头文件。

## 固定门禁

每次升级至少满足以下条件。

- 源码归档、大小和 SHA-256 与 `sources.json` 一致。
- 正式补丁只来自 `sources.json` 的 `patches`，研究补丁不得自动应用。
- 补丁回放前执行 `git apply --check`，应用失败立即停止，不保留 `.rej`。
- Android 目标使用 NDK Clang，Windows 主机辅助程序可以使用 MSVC。
- FFmpeg 只生成静态库，启用 JNI、MediaCodec、网络、mbedTLS、dav1d 和 WebP。
- `libmpv.so` 保留 55 个 `mpv_*` 导出，无主机 RPATH/RUNPATH，也不依赖任何主机路径。
- 内嵌编译路径可能因 `__FILE__`、构建系统和静态依赖诊断文本保留在只读字符串中；
  验收应检查动态段和运行时依赖，不能把这类只读文本误判为 DLL 或宿主库依赖。
- 所有 LOAD 段按 16 KB 对齐，通常在 `0x4000`，并在打包后通过 zipalign。
- HTTPS 证书校验开启时必须加载 Android 系统 CA，不能靠关闭校验绕过。
- 编译成功只证明产物可链接，起播、seek、倍速、HDR/SDR 和切页必须另行验收。

## 目录职责

| 路径 | 用途 |
| --- | --- |
| `patches/mpv/` | 已跟踪的源码清单、正式补丁、研究补丁和历史说明 |
| `tools/mpv-0.42.0-upgrade/` | 项目内可跟踪的 Windows 本机构建入口 |
| `tools/mpv-0.42.0-upgrade/sources/` | 下载归档和解压源码，Git 忽略 |
| `tools/mpv-0.42.0-upgrade/build/` | Meson/Ninja 中间目录，Git 忽略 |
| `tmp/mpv-0.42.0-upgrade/prefix/` | Android 静态依赖前缀 |
| `tmp/mpv-0.42.0-upgrade/ffmpeg/` | FFmpeg 工作源码和静态库 |
| `tmp/mpv-0.42.0-upgrade/evidence/` | 脱敏日志和 ELF 校验证据 |
| `dist/integration/mpv-0.42.0-20261125/` | 当前候选 APK，Git 忽略 |

构建目录不得放到 `C:\lib`、`C:\include` 或盘符根目录。Meson 使用
`-Dprefix=/` 时必须同时设置项目内的 `DESTDIR`，并让脚本再次校验前缀确实位于
项目 `tmp/` 下。

当前脚本仍记录这台机器的 SDK、Python、Visual Studio 和项目短路径。迁移电脑前先
检查 `android-arm64.ini`、`build_ffmpeg_with_vs.cmd`、`load_vs_environment.cmd`、
`build_ffmpeg.sh` 和 `run_ffmpeg_configure.py`。路径改变后重新执行 Python 语法检查、
`bash -n` 和一次完整 configure，不能直接复用旧机器生成的 `build.ninja`。

## 一、准备源码和补丁

1. 从组件官方仓库取得新版本归档，记录版本、字节数和 SHA-256。
2. 将归档解压到项目 `tmp/` 或已被忽略的 `tools/.../sources/`。
3. 对 mpv 维护一份相对原始归档的完整总补丁。不要继续叠加已经失配的旧分项补丁。
4. 从干净基线生成标准 unified diff。总补丁回放后必须与工作源码逐文件一致。
5. 更新 `sources.json` 的正式补丁、研究补丁和归档信息。

FFmpeg Git 快照按以下顺序固定。

1. 用 `git ls-remote <官方仓库> refs/heads/master` 读取当前提交，不再使用浮动的
   `master` 作为构建输入。
2. 记录提交 SHA、提交时间和标题。本轮为
   `bf11bea4dcb4578b53906d1f5290f5b6bcae2dc2`，
   `2026-11-25 04:05:36 +0000`，提交标题为
   `avfilter/dnn: add MIGraphX execution provider support to the ONNX backend`。
3. 从该 SHA 的官方归档获得完整源码，在项目 `tmp/` 中解压并计算长度和 SHA-256。
4. 在 `sources.json` 同时填写 `tag: master`、完整 `commit`、归档长度和 SHA-256。
5. 在一个干净的该提交源码树上先执行 `git apply --check`，不要用 `--reject`
   留下部分成功或无提示忽略的 `.rej`。

本轮源码归档此前保存为
`tmp/FFmpeg-bf11bea4dcb4578b53906d1f5290f5b6bcae2dc2.tar.gz`。归档来自
GitHub 对该提交生成的源码包，而不是仓库内当前工作区。

本轮 mpv 正式补丁为
[mpv-0.42.0-piliexo-adaptation.patch](../patches/mpv/mpv-0.42.0-piliexo-adaptation.patch)，
SHA-256 为
`36a3c55cdf06408af54f1862402bdb9c85cc7574614ecd4c58d8174ef863cffe`。

本轮 FFmpeg Android 系统 CA 补丁为
[ffmpeg-android-system-ca.patch](../patches/mpv/ffmpeg-android-system-ca.patch)，
SHA-256 为
`bd462ef9595e2547b4c3c0882e19f629017166399343815823a1657443b64524`。

本轮动态 HDR、运行中倍率提示和解码前丢帧仍共用
[ffmpeg-android-dynamic-hdr.patch](../patches/mpv/ffmpeg-android-dynamic-hdr.patch)。
最新 Git 把视频私有状态类型改为 `MediaCodecContext`，并调整了初始化段和 flush
上下文，因此该补丁已按新基线重新生成，SHA-256 为
`59e77515bb5f518dbe13f8ab5bdb6289eae49131e7c3ed0dee689a2a3a78e856`。
旧补丁虽然仍有大量 hunk 可以按偏移应用，但不能继续作为正式输入。

应用并复核正式补丁。

```powershell
python tool/prepare_mpv_sources.py `
  --mpv-source tools/mpv-0.42.0-upgrade/sources/mpv-0.42.0 `
  --ffmpeg-source tmp/mpv-0.42.0-upgrade/ffmpeg

python tool/prepare_mpv_sources.py `
  --mpv-source tools/mpv-0.42.0-upgrade/sources/mpv-0.42.0 `
  --ffmpeg-source tmp/mpv-0.42.0-upgrade/ffmpeg `
  --check
```

`prepare_mpv_sources.py` 会先校验正式补丁和研究补丁哈希，再只应用 `patches`。
不要再使用会按文件名通配并自动应用全部 FFmpeg 补丁的临时脚本。

## 二、准备第三方静态依赖

FFmpeg、libass 和 libplacebo 共享一组 Android 静态依赖。先在独立前缀中完成
mbedTLS、fribidi、dav1d、FreeType、libwebp 和 HarfBuzz 的构建，再进行 FFmpeg 配置。

| 依赖 | 使用方 | 本轮关键产物 |
| --- | --- | --- |
| mbedTLS | FFmpeg 网络/TLS | crypto、TLS、X.509 静态库及 PSA 辅助库 |
| fribidi | libass | `libfribidi.a` 和生成表 |
| dav1d | FFmpeg AV1 解码 | `libdav1d.a` |
| FreeType | libass | `libfreetype.a` |
| libwebp | FFmpeg WebP | webp、demux、mux、sharpyuv 静态库 |
| HarfBuzz | libass | HarfBuzz 及其子模块静态库 |

所有库必须与目标 ABI、API 24、`-fPIC` 和 NDK Clang 一致。静态依赖没有跨 ABI
兼容性，禁止直接把 Windows 库、arm64 库或官方预编译库混进 v7 构建。

Windows 下 fribidi 的生成程序不能直接运行 Android 产物。本轮使用
[prepare_fribidi_generators.py](../tools/mpv-0.42.0-upgrade/prepare_fribidi_generators.py)
在 Visual Studio 环境生成所需表，并用
[windows-native.ini](../tools/mpv-0.42.0-upgrade/windows-native.ini)
指定主机工具链。生成表成功后，目标 `libfribidi.a` 仍由 NDK 交叉编译。

第三方依赖版本发生变化时，应重新构建整组静态依赖和 FFmpeg。不要继续使用上一版本
留下的同名 `.a` 或头文件。

## 三、构建 FFmpeg 静态库

当前 Windows 构建入口为
[build_ffmpeg_with_vs.cmd](../tools/mpv-0.42.0-upgrade/build_ffmpeg_with_vs.cmd)。
入口支持分别指定源码、安装前缀和版本字符串，因此升级 FFmpeg 时不需要覆盖旧
9.0.1 工作树或复用其静态库。

```powershell
$env:FFMPEG_SOURCE_DIR = (
  Resolve-Path tmp/ffmpeg-git-bf11bea4-20261125
).Path
$env:FFMPEG_INSTALL_PREFIX = (
  Resolve-Path tmp/ffmpeg-git-bf11bea4-prefix
).Path
$env:FFMPEG_REVISION = "git-2026-11-25-bf11bea4"

cmd.exe /d /c "tools\mpv-0.42.0-upgrade\build_ffmpeg_with_vs.cmd"
```

入口脚本完成以下事项。

- 加载 Visual Studio x64 环境，供 FFmpeg 的 Windows 主机辅助程序使用。
- 把 NDK Clang 和项目 `tmp` 下的本地工具目录放到 `PATH` 前部。
- 先构建全部静态库，再以显式 `V=1` 安装，规避开源快照在 Git Bash 下的静默安装
  宏截断问题。
- 将五个正式静态库和对应 pkg-config 描述安装到项目临时前缀。
- 将源码目录设为 Git 仓库搜索上界，防止没有 `.git` 的源码归档误读外层项目提交。
- 通过 `FFMPEG_REVISION` 固定内嵌版本，避免版本字符串把 PiliExo 提交误写成 FFmpeg
  提交。

首次配置或修改 FFmpeg 开关时必须执行完整 configure。只有补丁只影响目标源码、
配置没有变化时，才使用以下变量做增量构建。

```powershell
$env:FFMPEG_SKIP_CONFIGURE = "1"
```

`baseline-build-flags.txt` 使用 `PROJECT_PREFIX` 占位符，不再保存旧电脑的
`D:/pyprogram/...` 路径。`run_ffmpeg_configure.py` 负责替换项目内前缀。目标链接器
和汇编器必须显式设为 NDK Clang，不能沿用以 `aarch64-linux-android-` 为前缀、
最终被 MSVC 工具链误认的旧组合。

FFmpeg 静态库的 pkg-config `Version` 必须填写源码生成的真实 ABI 版本，不能填写
应用版本或 Git 提交。本轮 `9.1.git` 的版本如下。

| 静态库 | ABI 版本 |
| --- | --- |
| libavcodec | 63.28.100 |
| libavformat | 63.21.100 |
| libavutil | 61.21.101 |
| libswscale | 10.6.100 |
| libswresample | 7.7.100 |

构建后至少确认以下配置为 `1`。

```text
CONFIG_JNI
CONFIG_MEDIACODEC
CONFIG_NETWORK
CONFIG_HTTP_PROTOCOL
CONFIG_HTTPS_PROTOCOL
CONFIG_TCP_PROTOCOL
CONFIG_TLS_PROTOCOL
CONFIG_MBEDTLS
CONFIG_LIBDAV1D
CONFIG_LIBWEBP
```

同时抽查 H.264、HEVC、AAC、FLV、MOV、HLS、matroska 等正式播放所需解码器和
解封装器，避免出现“库能链接，但视频协议或编码器没编进去”的假通过。

### 同步构建 Media3 音频扩展

FFmpeg 的上游提交由 `patches/mpv/sources.json` 统一固定。更新提交后，使用本机执行：

```powershell
python tools/mpv-0.42.0-upgrade/build_media3_ffmpeg.py
```

Media3 从相同的源码归档构建，只启用 AC-3、E-AC-3 和 TrueHD。索引和容器解析继续由 Media3 提取器处理。将脚本输出的双 ABI AAR 更新到 `android/app/libs/` 后，检查解码重置和 HDR 在线分轨的前后跳转。

## 四、构建 libass 和 libplacebo

[build_arm64.py](../tools/mpv-0.42.0-upgrade/build_arm64.py) 负责安装
libass、libplacebo 并构建 mpv。构建前执行以下检查。

- 交叉文件必须指向 NDK Clang、LLVM ar/strip 和本地 pkg-config。
- 所有目标参数包含 `-fPIC`，链接参数包含 `-Wl,-z,max-page-size=16384`。
- libass 保持静态库。当前关闭 fontconfig、DirectWrite 和 CoreText。
- libplacebo 保持静态库。当前启用 OpenGL，关闭 Vulkan、D3D11、着色器编译器等
  非目标依赖。
- libplacebo 的 C++ 部分需要显式加入 `c++_static` 和 `c++abi`。
- Meson 安装的只读文件在 Windows 下先恢复可写。
- 依赖前缀必须位于项目 `tmp/` 内。

依赖版本变化时，同名头文件必须覆盖旧文件。当前辅助脚本已改为覆盖复制，并在开始
构建前校验前缀边界。更稳妥的做法是在切换 libass 或 libplacebo 大版本时删除旧的
`tmp/mpv-0.42.0-upgrade/prefix`，然后从头重建全部静态依赖。

本项目使用精简的 [pkg-config.py](../tools/mpv-0.42.0-upgrade/pkg-config.py)
处理 Windows 构建。它必须继续支持版本比较、`Requires`、`Requires.private`、
静态依赖展开和 `--cflags-only-I`、`--libs-only-l`。路径中出现空格时使用项目内的
8.3 短路径，不能依赖普通字符串拼接。

## 五、构建 libmpv

mpv 使用 Meson 构建静态依赖汇总后的共享库。

```powershell
$env:MPV_BUILD_PREFIX = $env:FFMPEG_INSTALL_PREFIX
$env:FFMPEG_SOURCE_DIR = (
  Resolve-Path tmp/ffmpeg-git-bf11bea4-20261125
).Path
$env:MPV_BUILD_DIR = (
  Resolve-Path tools/mpv-0.42.0-upgrade/build
).Path + "\mpv-0.42-arm64-ffmpeg-bf11bea4"

python tools/mpv-0.42.0-upgrade/build_arm64.py
```

mpv 源码保持 v0.42.0 时，可只替换 FFmpeg 前缀和 Meson 输出目录。`build_arm64.py`
从 `FFMPEG_SOURCE_DIR` 读取各 `lib*version` 文件并生成 pkg-config 描述，避免继续
复制旧 9.0.1 的 ABI 版本。链路重新编译成功、导出表不缩短且 16 KB 门禁通过后，
这次 FFmpeg 独立升级才算进入候选。

当前 Meson 选项如下。

```text
-Dlibmpv=true
-Dcplayer=false
-Dgpl=false
-Dlua=disabled
-Djavascript=disabled
-Dvulkan=disabled
-Dmanpage-build=disabled
-Dhtml-build=disabled
-Dpdf-build=disabled
-Dtests=false
-Ddefault_library=shared
```

链接阶段保留 `--no-undefined`。静态 FFmpeg、libass、libplacebo、mbedTLS、dav1d
和 WebP 依赖必须完整进入共享库，C++ 运行时使用静态链接。Meson 可能把 NDK
宿主机目录写成 `RUNPATH`，链接前必须删除该参数，链接后再次检查动态段。

mpv 0.42.0 删除了 `display_sync_drift_dir`，旧适配中的清零语句不能再保留。
本项目已经把完整 0.42 兼容变化集中到总补丁，不要再把 0.41 分项补丁逐份硬套。
上游最新 Git 又删除了若干旧 FFmpeg 配置别名，本轮已从
`baseline-build-flags.txt` 移除不再匹配的 `latm`、`mpeg4` demuxer/parser 和
`hls`、`srt` protocol 参数；出现 `Option ... did not match anything` 时必须回查
当前提交，不能把警告当成无害输出长期保留。

## 六、mpv 0.42.0 的 TLS 默认值变化

这是本轮最关键的回归。

mpv 0.42.0 把 `--tls-verify` 默认值从 `no` 改为 `yes`。FFmpeg n9.0.1 以及本轮
Git 快照的 mbedTLS 后端在未配置 `ca_file` 时使用空 CA 链，HTTPS 请求会得到
`MBEDTLS_X509_BADCERT_NOT_TRUSTED`。界面表现可能只是“视频加载中”，但播放器初始化
和 Surface 创建其实都正常。

Android 下正确做法如下。

- 默认优先读取新版 Android 的 `/apex/com.android.conscrypt/cacerts`。该目录缺失或为空时使用 `/system/etc/security/cacerts`。
- 显式配置的 CA 路径优先。目录解析的正返回值表示失败的条目数，成功载入的证书仍可用于校验。没有载入任何根证书时应报错。单文件配置继续使用文件解析 API。
- 保持证书校验开启，不使用 `tls-verify=no` 规避问题。

本轮诊断证据中，错误核心出现 6 次证书不受信任和 4 次打开失败。修复后出现 2 次
HTTP 206，证书错误和打开失败均为 0，随后 HEVC 硬件解码、AudioTrack 和约 60 fps
渲染正常启动。脱敏证据见
[summary.json](../tmp/mpv-0.42.0-upgrade/evidence/device-log-20261125/summary.json)。

下一次升级 FFmpeg 或 mbedTLS 后，必须首先验证系统 CA 补丁仍能应用、目录解析路径
仍进入最终字符串表且 HTTPS 真机能打开媒体，不能只看动态库能否加载。

## 七、strip 与 ELF 静态门禁

先保留未 strip 核心或对应的 readelf 证据，再执行 strip。

```powershell
llvm-readelf --file-header --program-headers --dynamic libmpv.so
llvm-strip --strip-unneeded libmpv.so
llvm-readelf --file-header --program-headers --dynamic libmpv.so
llvm-readelf --dyn-syms --wide libmpv.so
```

本轮修复后的 arm64 核心结果如下。

- FFmpeg 内嵌版本为 `git-2026-11-25-bf11bea4`，不再误取项目提交。
- 文件大小 14,449,848 字节。
- SHA-256
  `03d9777563471afe64ae71565548fd786e91470255069a28f1c3b2228afce7a3`。
- ELF64 AArch64、共享库、`SONAME=libmpv.so`。
- 55 个 `mpv_*` 导出。
- 4 个 LOAD 段全部 `0x4000` 对齐。
- 无 `RPATH`、无 `RUNPATH`，字符串表中没有需要运行时解析的宿主 DLL 或宿主库路径。
- 必需系统库只有 Android 平台库，静态第三方依赖已经进入核心。
- 字符串表存在系统 CA 路径和少量只读编译源码路径，不影响 APK 运行依赖。

`mpv_client_api_version` 从 0.41 的 2.5 升到 0.42 的 2.6。这是正常客户端 API
版本变化，不应为了保持数值相同而修改源码。要继续确认 media_kit 使用的调用仍被
导出并与 API 2.6 兼容。

## 八、生成 APK

### 构建 ARMv7 核心

复用经 SHA-256 核对的上游归档。将 FFmpeg 从同一归档干净解包到 ARMv7 工作目录
的 `ffmpeg/` 下，并用 `prepare_mpv_sources.py` 应用清单中的正式补丁。
mpv 和第三方依赖源码沿用 `tools/mpv-0.42.0-upgrade/sources/` 下的固定版本。

```powershell
$armv7Work = (New-Item -ItemType Directory -Force tmp/mpv-armv7).FullName
python tools/mpv-0.42.0-upgrade/build_armv7.py dependencies --work $armv7Work

$env:FFMPEG_ANDROID_ABI = "armeabi-v7a"
$env:FFMPEG_SOURCE_DIR = Join-Path $armv7Work "ffmpeg"
$env:FFMPEG_INSTALL_PREFIX = Join-Path $armv7Work "prefix"
$env:FFMPEG_SKIP_CONFIGURE = "0"
$env:FFMPEG_REVISION = "git-2026-11-25-bf11bea4"
cmd.exe /d /c "tools\mpv-0.42.0-upgrade\build_ffmpeg_with_vs.cmd"

python tools/mpv-0.42.0-upgrade/build_armv7.py mpv --work $armv7Work
```

目标编译器为 `armv7a-linux-androideabi24-clang`。Windows 主机只负责编译
FriBidi 表生成器和 FFmpeg 主机辅助程序。Meson 对 Android 目标使用 `/` 作为逻辑
安装前缀，实际安装时用 `DESTDIR` 指向项目 `tmp`，避免写入盘符根目录。
最终核心位于工作目录的 `mpv/libmpv.so`，strip 后单独核对 ELF32/ARM、55 个导出、
16 KB LOAD 对齐、FFmpeg 版本以及 Android 音频驱动。

### 生成 APK 与签名

正式包必须先由项目脚本生成版本和源码提交元数据。

```powershell
lib/scripts/build.ps1
```

Flutter 构建必须把 `pili_release.json` 传入 AOT。

```powershell
flutter build apk --release `
  --target-platform android-arm64 `
  --split-per-abi `
  --dart-define-from-file=pili_release.json
```

遗漏 `--dart-define-from-file` 会导致 `verify_release_apk.py` 报 AOT 源码提交或版本
不一致，不能绕过该检查。

随后使用项目脚本替换同名 `libmpv.so`、清理其他 ABI、zipalign 16 KB，并用原正式
证书签名。

```powershell
python lib/scripts/package_android_native.py `
  --base <同 ABI 的项目 APK> `
  --native tools/mpv-0.42.0-upgrade/build/mpv-0.42-arm64/libmpv.so `
  --out <候选 APK> `
  --abi arm64-v8a `
  --tools C:/Android/Sdk/build-tools/37.0.0 `
  --expected-native-sha256 <libmpv SHA-256>
```

脚本会逐字节确认除目标核心外的未替换条目、设备架构、核心哈希、原证书和 16 KB
对齐。成功后自动删除 `.unsigned.apk` 和 `.aligned.apk` 中间文件，只保留 APK 和
`.artifact.json`。

本轮 FFmpeg Git 独立升级候选为
`dist/integration/ffmpeg-git-bf11bea4-20261125/PiliExo_android_v26.11.24_ffmpeg-git-bf11bea4_arm64-v8a.apk`，
49,894,677 字节，SHA-256
`71cd70e0b6974398fb04e0a053eb9073048ec3979475dcab73fe5e83e3dd30ee`。
包内核心 SHA-256 为
`8d4c34ef167d9e586c4c3df20eabb2686303b55c52eee7c83a9fc3a69a010482`。
该候选已在 MEP-AN00 上实际起播：一次渲染采样为 73/s 入队、71/s 渲染、0/s
丢弃，AudioTrack 已启动，未出现证书错误、打开失败、MissingPlugin 或崩溃。
seek、倍速、HDR/SDR、字幕、音轨切换和冷启动三大页首切仍需继续人工验收。

## 九、发布前静态门禁

至少执行以下检查。

```powershell
lib/scripts/verify_android_plugins.ps1

python tool/verify_release_apk.py `
  --source-commit <git rev-parse HEAD> `
  --version <versionName> `
  <APK>

python -m unittest discover -s test/native -v
```

另外使用 `aapt2 dump badging`、`apksigner verify --verbose` 和
`zipalign -c -P 16 -v 4` 核对包名、versionCode、versionName、ABI、签名方案和对齐。
本机原生单测需要 `PATH` 中有能生成 Windows 可执行文件的 C 编译器；本轮临时包装
NDK Clang 为目标为 `x86_64-pc-windows-msvc`，复用 Visual Studio 头文件和 linker，
6 项测试通过。包装器只用于测试，不进入仓库或 APK。

候选只通过静态门禁时，记录必须写成“静态通过”，不能写成“真机通过”。

## 十、真机验收

安装后由用户手动进入视频页。ADB 只负责安装、清空/读取日志和核对包哈希。

建议的日志判据如下。

1. HTTPS 请求返回 `HTTP/1.1 206 Partial Content`。
2. 没有 `certificate is not correctly signed by the trusted CA`。
3. 没有对应媒体 URL 的 `Failed to open`。
4. 出现目标硬件解码器创建和启动日志。
5. AudioTrack 成功启动。
6. Surface 尺寸与媒体尺寸一致。
7. 渲染日志持续更新，播放中没有持续 0 fps。

随后继续检查 seek、倍速、长按加速、HDR10、SDR、Dolby Vision P5 回退、字幕、
音轨、后台返回、音频焦点和暂停恢复。更新 mpv 时还要检查现有原生 HDR 选项和
MediaCodec 私有参数是否仍被新核心识别。

## 十一、设备端 APK 回读

PowerShell 的 `adb exec-out cat ... > file.apk` 可能按文本处理输出，导致 APK 被
截断。需要读取二进制时使用 Python 的 `subprocess.run(capture_output=True)`，
读取 `bytes` 后直接写入文件并计算 SHA-256。

最终候选必须同时满足以下条件。

- 本地 APK SHA-256 与预期一致。
- 设备端回读 APK SHA-256 一致。
- `pm path` 指向当前安装包。
- versionCode、versionName 和首次安装时间状态符合覆盖安装预期。

## 十二、本轮踩坑清单

| 问题 | 下一次规则 |
| --- | --- |
| 旧补丁使用 `git apply --reject` 后仍有部分成功，`.rej` 被忽略 | 先 `--check`，失败立即停止，不留 `.rej` |
| 旧分项补丁与 mpv 0.42 源码失配 | 优先维护相对干净基线的总补丁 |
| FFmpeg 参数依赖旧电脑 `D:/pyprogram` | 使用 `PROJECT_PREFIX` 占位符和项目内前缀 |
| Windows `--cross-prefix` 误用 MSVC 链接目标 | 显式指定 NDK Clang 作为 ld/as |
| Meson 错误的 `DESTDIR` 写入 `C:\lib`、`C:\include` | 安装前断言前缀位于项目 `tmp/` |
| 同名依赖头文件未覆盖，可能混入旧版本 | 升级时覆盖头文件或删除整套前缀重建 |
| Meson 把 NDK 宿主机目录写进 `RUNPATH` | 链接前删除，strip 后再次核对动态段 |
| FFmpeg pkg-config 版本误写应用版本 | 使用真实 ABI 版本 |
| 路径含空格导致 pkg-config/clang 参数拆分 | 使用 8.3 短路径并保证参数边界 |
| Git 源码归档没有 `.git`，版本脚本向上找到 PiliExo 提交 | 设置 Git 搜索上界并显式传 `FFMPEG_REVISION` |
| FFmpeg 9.1 的静默安装宏在 Git Bash 下产生未闭合引号 | 构建与安装分开，安装阶段使用 `V=1` |
| FFmpeg 最新版移除部分旧 demuxer/parser/protocol 别名 | 删除无效参数并重新执行完整 configure，不留警告 |
| mpv 0.42 默认开启 TLS 校验但无 CA | 加载 Android 系统 CA，不关闭校验 |
| 只看核心大小或编译成功 | 必须核对 55 个导出、依赖、16 KB 和真机起播 |
| PowerShell 文本重定向截断二进制 APK | 用 Python 读取 `adb exec-out` 字节流 |
| 诊断插桩结束后可能残留在正式源码 | 诊断代码用临时开关，验证后立即删除并检查 diff |
| 签名脚本留下 aligned/unsigned APK | 成功后自动删除中间文件 |
| 错误候选、诊断包、重复补丁长期留在输出目录 | 及时清理，只保留最终 APK 和脱敏证据 |

## 十三、收尾纪律

每次升级结束后完成以下动作。

1. 删除失败候选、诊断 APK、重复补丁、一次性源码副本和失效构建缓存。
2. 删除原始 logcat、带时效签名的 URL、账号参数和设备标识，只保留脱敏摘要。
3. 保留最终 APK、`.artifact.json`、小型 ELF 证据和可复现补丁。
4. 检查 `git status`、`git diff --check` 和全部补丁哈希。
5. 未提交、未发布、未做真机验收时，在 `STATUS.md` 和中文进度中明确写出。
6. 正式发布前重新构建，并确认 AOT 内嵌提交与最终源码提交一致。
