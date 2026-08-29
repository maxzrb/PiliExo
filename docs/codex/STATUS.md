# PiliExo AI 工作状态

- 更新时间：2026-08-29 19:03 (+08:00)
- 工作分支：`feature/android-media3-hdr`
- 分析基线：`7a2edd7c9`
- 发布提交：`7a2edd7c9fd1ee9aaaf71e5052301ed04b60c5e2`
- 目标：PiliExo 仅 Android 在线 UGC/PGC HDR 使用 Media3 原生 SurfaceView；SDR、直播和离线保持 mpv；应用包名独立为 `com.maxzrb.piliexo`，外观磨砂效果可配置；暂不接入 Android Kyant 液态玻璃。当前 v26.8.29.4 已覆盖更新下载弹窗交互，版本号保持不变。

## 已完成

- 添加 Media3 1.11.0、OkHttp 5.3.0 依赖及原生 `SurfaceView` 布局。
- 注册 `piliexo/media3_hdr_surface` Hybrid Composition PlatformView、MethodChannel 和 EventChannel。
- 实现 HDR 会话、分离 fMP4 音视频合并、请求头、主/备用 URL、Range 续传、字幕和 HDR 格式事件。
- Dart 播放控制器统一接入 Media3/mpv，支持 HDR 画质路由、状态恢复、原生字幕、倍速、画面模式和失败回退。
- HDR 模式禁用 Flutter 缩放/镜像/Anime4K/截图入口，保留 Flutter 控制栏和弹幕。
- 设置页加入“HDR 播放器”开关，默认启用 Media3 原生 HDR。
- 添加 Dart 路由测试和 Android 参数、403/5xx、Range、断流续传备用 URL 单测。
- 根据真机截图修复 HDR/SDR 切换时 `Obx` 构建期写状态导致的 Flutter 红屏，并为 SurfaceView 增加显式隐藏、清空和重新挂载恢复。
- 根据最新真机截图修复 HDR 返回播放列表时清屏时序过晚：HDR 路由退出前先拦截返回并发起 Surface 清理，原生隐藏改为 `GONE`。
- 应用标识、源码链接、问题反馈和 Release 更新入口切换到 `maxzrb/PiliExo`；ModelScope 镜像固定为 `AerithDream/PiliExo`。
- 更新检查改为按 `vYY.M.D.build` Release 标签比较，Android 下载先探测 ModelScope，失败后回退 GitHub Release 资产。
- 所有底栏和侧栏导航项统一使用 Android 原生可调振幅震动，设置页新增 1–255 强度调节。
- 新安装默认开启震动反馈，默认强度为 80；拖动强度滑块时即时震动，取消调节不保存临时值。
- 普通视频两个画质选择入口统一将 8K、HDR Vivid、杜比视界、HDR 真彩置于前列；“蜂窝网络”文案统一改为“移动数据”。
- 顶栏、底栏和普通页面 AppBar 增加磨砂半透明效果；浮动底栏继续使用原生 Flutter 渲染，不影响 HDR SurfaceView。
- Android Release 改为 `com.maxzrb.piliexo`，仅生成 `armeabi-v7a` 和 `arm64-v8a`；启用 R8、资源压缩和对应 ABI 下载选择。
- 关于页和应用元数据描述精简为“支持HDR的PiliPlus修改版”，并修正透明主题下浮动底栏的磨砂底色。
- 外观设置新增磨砂总开关与轻薄、标准、浓厚三档效果，配置变化会即时刷新顶栏、底栏、浮动底栏和特殊页面顶栏；关闭时恢复不透明底色。
- 根据真机截图移除顶栏与状态栏交界处的顶部边框，并降低轻薄档遮罩不透明度，使磨砂背景更通透。
- 移除主底栏和浮动底栏磨砂容器的顶部边框，避免底栏顶部出现突兀亮线。
- 修正震动反馈设置项初始开关显示为关闭的问题；新安装显示为开启，已有用户明确关闭的选择保持不变。
- 新增 `docs/发布流程.md`，记录测试阶段冻结版本号、发布时递增、双 ABI 构建、签名、GitHub/ModelScope 发布和回滚要点。
- 已创建 `maxzrb/PiliExo` fork、`AerithDream/PiliExo` 数据集并发布 `v26.8.28.1`。
- 按远端最新 Release `v26.8.28.1` 的 N+1 规则发布正式版 `v26.8.28.2`，GitHub 与 ModelScope 双源资产均已上传。
- 已从 PiliPlus 上游同步 3 个提交：`37ae9cf2d`、`4da811080`、`9058ac144`，分别修复下拉框下划线、补充移动端缓存 URI 复制入口和修正字体加载提示。
- 修正版本元数据：本机 `android/local.properties` 的旧 `flutter.versionCode=3` 与 Dart `SNAPSHOT` 默认值曾造成错误显示，现已恢复为 `26.8.28+2`；测试构建不再递增版本号，远端正式 N 仍为 2。
- 新增精简 FFmpeg 音频扩展 AAR，为 AC-3、E-AC-3/E-AC-3-JOC 和 Dolby TrueHD 提供硬件优先、软件回退路径；仅随 Android arm64/v7a 包发布。
- 已按官方 BiliPai 的实际实现核对环境背景方案：视频当前帧使用 96×54 小图采样，播放中约每 66ms 更新，状态栏顶部单独显示并做模糊与暗色遮罩；没有把模糊施加到播放器画面或做视频转场。
- 新增状态栏环境帧链路：SDR 从现有视频 RepaintBoundary 采样，HDR 从 Media3 `SurfaceView` 使用 Android `PixelCopy` 采样；HDR 播放仍保持原生 SurfaceView，不经过 SurfaceTexture、TextureView 或 Flutter Texture。
- 新增播放器洞察：参考 BiliPai 的概览、视频、音频、播放和事件信息，在视频页“更多设置 → 播放器洞察”打开，实时显示 Media3 HDR 或 mpv 已报告的解码器、格式、色彩、缓冲、首帧和掉帧信息。
- 中部上滑/下滑切换全屏时，在真正越过手势阈值并执行切换的瞬间复用统一振幅震动反馈。
- 播放器洞察不再受当前后端实例条件隐藏，视频页“更多设置”靠前固定显示；设置页“播放器设置”新增“显示 / 智能 / 不显示”三档，默认智能。
- 新增播放器洞察摘要 HUD：显示档常驻，智能档在起播首次拿到有效播放器数据或检测到新增掉帧时显示 5 秒并用 350ms 渐隐，不显示档关闭自动摘要；摘要已下移，点击摘要所在的黑色半透明 surface 后由同一层直接扩展为详情层，点击遮罩或关闭按钮收起，不再弹出二级对话框。
- 智能洞察同步监听播放器控制条状态：控制条/进度条呼出时优先接管显示并覆盖当前起播/掉帧事件窗口；控制条关闭时同步关闭洞察、收起详情并取消这次已被覆盖的事件窗口；未呼出控制条时，起播/掉帧事件仍独立显示 5 秒；显示和不显示模式不受该联动影响。
- 发布流程已明确正式标签按发布日期生成 `vYY.M.D.N`，日期变化时当天序号从 `.1` 开始；本次由远端 `v26.8.28.2` 正确推进为 `v26.8.29.1`，应用版本为 `26.8.29+1`。
- 已发布 `v26.8.29.1`：GitHub Release 与 ModelScope `AerithDream/PiliExo` 双源均包含 arm64-v8a 和 armeabi-v7a 资产。
- 已生成本地固定正式签名：`android/piliexo-release.jks`（PKCS12、RSA 4096、有效期 10000 天），`android/key.properties` 已接入 Gradle 且均被 Git 忽略。
- 修复播放器洞察详情跟随控制条隐藏逻辑被收起的问题：查看详情期间控制条状态变化只清理自动摘要，不再关闭详情。
- 调整全屏播放器洞察详情布局：详情沿用摘要的实际宽度和右上位置，仅向下扩展高度，避免详情面板铺满播放器。
- 底栏重复点击首页或动态触发刷新时，改为先显示对应现有下拉刷新动画，再执行原有刷新回调；滚动未到顶部时仍保持只回到顶部的行为。
- 为首页各内容 tab 和动态各 tab 的现有 `RefreshIndicator` 绑定程序化触发 key，未改变手动下拉刷新路径。
- 补齐播放器洞察“视频”详情分组中的视频码率展示，复用已有的 `videoBitrate` 数据，并增加回归测试。
- 已发布正式版 `v26.8.29.2`，应用版本为 `26.8.29+2`，发布提交为 `68b9a377f9dc13aabd99d265e67bcaec81f11207`；GitHub 与 ModelScope 均已同步双 ABI 资产。
- 修复播放器洞察视频码率数据链路：DASH 轨道码率写入播放器数据源，Media3 HDR、mpv 及 HDR 回退路径均使用该值补齐视频码率；概览和“视频”分组在有码率数据时都会显示。
- 按 BiliPai 的分档策略调整全屏播放器洞察摘要和详情位置/尺寸：摘要按屏幕宽度分档定位，详情固定在右侧并限制为约 42% 宽、最大 440×360，普通窗口布局不变。
- 检查更新的 Android 下载流程接入 Aria2-next 2.6.7：内置 ARM64 执行文件，使用 32 分片、断点续传和 SHA-256 校验，下载完成后自动唤起系统 APK 安装器；不支持 ARM64 时回退应用内 HTTP 下载。
- 将 Flutter 工具链统一锁定为 `3.47.2`：`.fvmrc`、`pubspec.yaml`、`pubspec.lock` 和实际 SDK 均由 `lib/scripts/verify_flutter.ps1` 校验，5 个 GitHub Actions 工作流统一从 `.fvmrc` 读取并在构建前校验。
- 将 Android Kotlin 跨盘缓存修复写入 `android/gradle.properties`：默认 `kotlin.incremental=false`；保留 `android.builtInKotlin=false` 和 `android.newDsl=false` 兼容开关，避免当前 Flutter Gradle 插件与 AGP 9 新 DSL 的类型冲突。
- 将固定 Flutter 工具链、跨盘构建约束和标准发布检查命令写入 `docs/发布流程.md`，并在本次 `v26.8.29.3` 发布中按该流程执行。
- 已发布正式版 `v26.8.29.3`，应用版本为 `26.8.29+3`，发布提交为 `4b3baa808180c40c6857b71f0701ee70e4bc3ec5`；GitHub 与 ModelScope 均已同步双 ABI 资产。
- 修正播放时画质/音质切换行为：只更新当前播放器，不再回写默认画质、移动数据画质、默认音质和移动数据音质；设置页手动修改仍正常持久化。
- 新增独立的“Android 液态玻璃”开关，默认关闭，Android 13（API 33）以下显示禁用和版本提示，开关即时生效且与磨砂设置相互独立。
- 通过 Kyant Backdrop 2.0.0 和 Android Compose PlatformView 接入三类紧凑控件：浮动/固定底栏、首页搜索胶囊和非播放器页面主悬浮按钮；导航交互、文字、语义和震动仍由 Flutter 保持。
- 修复 `BiliDocumentsProvider` authority 硬编码导致 Debug 包 `com.maxzrb.piliexo.debug` 与已安装 Release 包冲突的问题，改为使用构建变体 `${applicationId}.MTDataFilesProvider`。
- 修复液态玻璃启用后的崩溃风险：取样改为独立 Bitmap 快照，限制每个控件为单一 Kyant 渲染层，并增加启动探测保护；升级后已有开启状态先安全回退，异常后下次启动不重复创建原生视图。
- 原生层从混合合成的 `FlutterImageView` 取样，按 33ms 限流并在视图不可见、窗口失焦或应用暂停时停止；连续取样失败自动熔断回退现有磨砂，用户开关不清除。
- 新增液态玻璃 Dart/Android 单测及 Kyant Apache-2.0 许可说明；本轮保持 `26.8.29+3`，未创建新 Release。

## 验证

- 本轮 `flutter test --no-pub`：14/14 通过；液态玻璃测试覆盖默认关闭、持久化/即时同步、API 33 门槛、启动探测标记、状态复制和预设分支。
- 本轮目标文件 `flutter analyze --no-pub`：无问题；全量 `flutter analyze --no-pub --no-fatal-infos` 的项目既有提示未作为错误处理。
- Android `:app:testDebugUnitTest --tests com.maxzrb.piliexo.AndroidLiquidGlassPluginTest`：通过，覆盖原生参数合并、坐标换算、可见/焦点生命周期、33ms 限流常量和三次失败熔断。
- Android 默认 `android\gradlew.bat :app:compileDebugKotlin --console=plain`、原生单测与 `:app:assembleDebug --console=plain --warning-mode=none`：通过；最终 Debug APK `build/app/outputs/flutter-apk/app-debug.apk` 为 `214,432,947` bytes，SHA-256 `95FC380AD172C85F82EDB7AF9A4B29119F103DB2E1F59231AB918F9C8DE03A3A`，已核验包含 Kyant 许可资产。
- `git diff --check`：通过；工作区继续保留用户未跟踪目录 `tmp/`，本轮源码和记录改动尚未提交；Debug 合并 Manifest 已确认使用 `com.maxzrb.piliexo.debug.MTDataFilesProvider`，Provider 冲突已排除，但设备仍拒绝 USB 安装授权，未完成最终 Debug 包的 ADB 真机验收。

- `flutter test --no-pub`：通过，8 个测试全部通过，其中包含 Android ABI 资产选择测试；本机 SDK 为 3.47.1，而同步后的 `pubspec.yaml` 要求 3.47.2，普通 `flutter test` 因版本解析被阻止。
- Media3 1.11.0 + OkHttp 5.3.0 独立 Android API 工程：Kotlin 编译及 `HdrMedia3SourceTest` 通过（含 5xx、Range 和断流续传）。
- 目标文件定向 `flutter analyze`：无 error，仅有 lint info。
- 本轮播放器洞察修复后，目标文件 `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 8/8 通过，`git diff --check` 通过；未生成 APK，未进行真机验收。
- 本轮底栏刷新动画改动后，11 个相关 Dart 文件 `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 8/8 通过，`git diff --check` 通过；未生成 APK，未进行真机验收。
- 本轮播放器洞察码率修复后，相关模型和测试文件 `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 9/9 通过，`git diff --check` 通过；未生成 APK，未进行真机验收。
- `v26.8.29.2` 发布构建：`flutter test --no-pub` 10/10 通过；定向 14 项 Dart 文件 `flutter analyze --no-pub` 无问题；`git diff --check` 通过。
- `v26.8.29.2` 双 ABI 正式 APK 已通过 `aapt2` 核验：包名 `com.maxzrb.piliexo`、`versionName=26.8.29`、`versionCode=2`，分别只含 `arm64-v8a` 或 `armeabi-v7a`，且包含对应 `libffmpegJNI.so`。
- `v26.8.29.2` 两包均通过 `apksigner` V2 签名验证，签名证书 DN 为 `CN=PiliExo, O=AerithDream, C=CN`；arm64 `25,681,072` bytes，SHA-256 `E3988B841C173F8D3D2595299A639FC2EE2C1541CE1F80665832F3FB0A83BF92`；v7a `25,550,590` bytes，SHA-256 `D0876E6967C7DC5F182925E8083C4B5F2E62E0A92E1500715C018904489556E1`。
- GitHub Release：<https://github.com/maxzrb/PiliExo/releases/tag/v26.8.29.2>；ModelScope：<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.2/PiliExo_android_v26.8.29.2_arm64-v8a.apk>、<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.2/PiliExo_android_v26.8.29.2_armeabi-v7a.apk>。
- `v26.8.29.3` 发布验证通过：GitHub 两个资产状态为 `uploaded`，ModelScope 两个镜像地址 HTTP 200；arm64 SHA-256 `F127645D45EB69E74616FFD4937BA9A9D2EFD819842CA1FE4C066B3770B71224`，v7a SHA-256 `D9D871CC1C7F0C6EB6E0ABC42ABE301F6C5FDB7CCF818B1B65F7FA3D58136565`，镜像 `X-Linked-ETag` 与本地值一致。
- `v26.8.29.3` APK 已由 `aapt2` 核验包名 `com.maxzrb.piliexo`、`versionName=26.8.29`、`versionCode=3` 和对应 ABI；两个包均通过 `apksigner` V2 签名验证。
- 本轮 Android Debug APK 已通过 Gradle `assembleDebug -Pkotlin.incremental=false`：包名/更新权限/FileProvider 已合并，APK 内含 `assets/aria2-next/arm64-v8a/aria2-next`（13,121,080 bytes）及许可证说明；APK `154,189,619` bytes，SHA-256 `AA47C5ADB927F328175D3BB757F3966AF8F5744E8BDAE37199DBF65995EA6FDC`。
- 本轮 `flutter test --no-pub`：11/11 通过；相关文件 `flutter analyze --no-pub --no-fatal-infos` 无 error，仅保留控制器既有 4 条 info；Android `:app:compileDebugKotlin -Pkotlin.incremental=false` 通过；`git diff --check` 通过。
- 本轮 Flutter 3.47.2 工具链校验通过；全量 `flutter test --no-pub` 11/11 通过；全量 `flutter analyze --no-pub --no-fatal-infos` 无 error，仅有项目既有 42 条 info。
- Android 默认 `android\gradlew.bat :app:compileDebugKotlin --console=plain` 在不追加 `-Pkotlin.incremental=false` 时构建成功；标准 `flutter build apk --debug --no-pub` 也成功，产物 `build/app/outputs/flutter-apk/app-debug.apk` 为 208,644,128 bytes，SHA-256 `EC4C6A6DAD3FDC5640E57F0E11A1229A38D96AAC707A1F4AB54EFE5F2793E3F7`，并核验包含 Aria2-next ARM64 资源、许可证说明和 FileProvider。
- ModelScope 两个路径回读后 SHA-256 与本地产物完全一致；发布工作区继续保留用户未跟踪目录 `tmp/`，未将其纳入提交。
- `git diff --check`：通过；仅报告仓库既有的 LF/CRLF 自动转换提示。
- 使用项目补丁脚本修复 Flutter 3.47.1 与项目 `material_ui` 的基线兼容后，Android `assembleDebug` 构建通过。
- APK 已生成：`build/app/outputs/flutter-apk/app-debug.apk`，201236035 bytes；最新 SHA-256 为 `ABCC62569508456C5B7872AB725F611BBF227B88B5AE5FDE95E9E3A9A44BCBDC`。
- 全量 `flutter test`：通过。
- Android `assembleRelease`：通过（缓存 Gradle、Media3 1.11.0、OkHttp 5.3.0）。
- Android `:app:testDebugUnitTest -Pkotlin.incremental=false`：通过（本轮加入 FFmpeg 音频扩展后复验）。
- Android Gradle 9.5 `:app:assembleRelease -Pkotlin.incremental=false -Psplit-per-abi=true -Ptarget-platform=android-arm,android-arm64`：通过；生成 arm64/v7a 测试包，均为 `versionCode=2`，并核验 `libffmpegJNI.so` 与对应 native ABI。
- AAR 与 release APK 核验通过：保留 `FfmpegAudioRenderer`，APK 不含 x86/x86_64；E-AC-3-JOC 软件路径以 PCM 出声为目标，不保证 Atmos 对象直通。
- 本轮测试 Release（未发布，版本保持 `26.8.28+2`）已生成：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 26,930,502 bytes，SHA-256 `D5A1FCEBBEA942A7A014BAAB5D7A2BB6377645800AF86B28EC935DBB5A16B42A`；`app-armeabi-v7a-release.apk` 26,808,350 bytes，SHA-256 `C4593E3357539BFE0CA454B1681C48DBE9747276B0F55DC4F54FBFC50D409183`。
- 本轮使用 `aapt2` 核验两包均为 `com.maxzrb.piliexo`、`versionName=26.8.28`、`versionCode=2`，且各自只含目标 ABI；`flutter test --no-pub` 8/8 通过，`flutter analyze --no-pub` 无 error，仅保留项目既有 42 条 info。
- 本轮包含新 HUD/设置/手势反馈的测试 Release 已重新生成：arm64 `26,932,238` bytes，SHA-256 `3FC08D7B22227B034F265D5AD67B48357731BD28AD494DBE029D2CB2E0DBBD28`；v7a `26,802,938` bytes，SHA-256 `1AB745AE2A5F235578BCB58090FE4412A6BBEE1FA65E02A020756EF5FA09E849`。
- 本轮洞察内联展开修复的测试 Release 已重新生成：arm64 `26,937,774` bytes，SHA-256 `CEB32DA13C25A00A3B7DD497B7BA9E545A7BA8C8F24A8B76AEDD0D5292B73B46`；v7a `26,807,498` bytes，SHA-256 `FCDC791140051CBB431FF0097C403B9E06589BEC0224A7FD2E7E797C3963FD46`。
- 本轮使用 `aapt2` 核验两包均为 `com.maxzrb.piliexo`、`versionName=26.8.28`、`versionCode=2`，分别只包含 `arm64-v8a` 或 `armeabi-v7a`；`flutter test --no-pub` 8/8 通过，`flutter analyze --no-pub` 无 error，仅保留项目既有 42 条 info。
- 本轮按 BiliPai 黑色半透明 surface 扩展逻辑重构后的测试 Release 已重新生成：arm64 `26,935,290` bytes，SHA-256 `5C3BD4F840C4442ECDDC2EDB96672ADE1D360D29FEC6C0564B00028EA77B73A7`；v7a `26,810,654` bytes，SHA-256 `B1B2F9639ECAEF5C40A99DB10A4D880DE4B96A7C2A152DFE696744A9F32688FC`。
- 本轮 `aapt2` 核验两包均为 `com.maxzrb.piliexo`、`versionName=26.8.28`、`versionCode=2`，分别只包含目标 ABI；`flutter test --no-pub` 8/8 通过，`flutter analyze --no-pub` 无 error，仅保留项目既有 42 条 info。
- 本轮智能模式控制条联动修复的测试 Release 已重新生成：arm64 `26,939,058` bytes，SHA-256 `05B3D22D020EF57558E0BE9BC7FE0C223A3C97C6FB3D69E1B348641FB138901F`；v7a `26,807,238` bytes，SHA-256 `788BD377A987C292BBC655E8E36825183461F564385527E550A7B14278D67A8B`。
- 本轮再次核验 APK 均为 `com.maxzrb.piliexo`、`versionName=26.8.28`、`versionCode=2`，分别只包含 `arm64-v8a` 或 `armeabi-v7a`；Flutter 单测 8/8、Flutter analyze 无 error、Gradle 9.5 Release 构建通过。
- 本轮修正智能模式可见性边界：未呼出控制条时起播/掉帧提示独立显示 5 秒；控制条打开时优先接管并覆盖事件提示，控制条关闭时同步关闭洞察并取消这次已被覆盖的事件窗口。测试 Release 已重新生成：arm64 `26,938,810` bytes，SHA-256 `B68176B0BFB53EF77AE49FFE708BB3D9233EF5529D7CF1FBA9C05DF40B97C95F`；v7a `26,807,554` bytes，SHA-256 `A35D54C62FA438441F9273AB5C6D5A3CBA7B4063160D9A0146F261C62B6A5BE9`。
- 本轮再次通过 `aapt2` 核验包名、`versionName=26.8.28`、`versionCode=2` 与双 ABI；`flutter test --no-pub` 8/8、`flutter analyze --no-pub` 无 error（仅项目既有 42 条 info）、Gradle 9.5 Release 构建通过。
- 本轮最终 Release 测试包包含智能洞察控制条优先级、事件窗口关闭语义和全屏摘要右移修正（全屏右侧内缩 36dp）；arm64 `26,939,018` bytes，SHA-256 `DB7EDEE5882ACB802040E2A48A75C197223AC089011A8A3E9AA167E792FEA49A`；v7a `26,807,566` bytes，SHA-256 `78D6B747E6CF5D9C90939F661B882E973E089532A3A71DB1499374E1B062223A`。
- 最终包再次通过 `aapt2` 核验 `com.maxzrb.piliexo`、`versionName=26.8.28`、`versionCode=2` 和单一对应 ABI；PiliPlus 上游 `main` 没有本地尚未同步的独有提交。
- Release APK：`dist/PiliExo_android_v26.8.28.1.apk`，68,793,128 bytes；SHA-256 为 `9D64CAD5C991485E4DCB323C2DAA8FA2DC5F8B300C97EA7DD8C71190B2D5664F`；包名保持 `com.example.piliplus`，显示名为 `PiliExo`。
- v26.8.28.2 arm64 Release APK：`dist/PiliExo_android_v26.8.28.2_arm64-v8a.apk`，26,601,707 bytes；SHA-256 为 `94EA78F3AA2458B9C56F264ED8A99BAF8971AD0390B010FABFD7C558C6B371A6`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- v26.8.28.2 v7a Release APK：`dist/PiliExo_android_v26.8.28.2_armeabi-v7a.apk`，26,480,705 bytes；SHA-256 为 `E9234886FC779CBC424A8B6965AB256353753549FFE973EDEBAA8C18EE4B196C`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- v26.8.28.2 Release 仅包含 `arm64-v8a`、`armeabi-v7a` 两种 native ABI；相较 v26.8.28.1 通用包，单包体积降低约 61%。
- v26.8.28.3 arm64 Release APK：`dist/PiliExo_android_v26.8.28.3_arm64-v8a.apk`，26,603,903 bytes；SHA-256 为 `2B13DAA38924C02708549A61F09AFF7AA2844425AD8BC79C994D6E9DE390E686`；包名为 `com.maxzrb.piliexo`，versionCode 为 3。
- v26.8.28.3 v7a Release APK：`dist/PiliExo_android_v26.8.28.3_armeabi-v7a.apk`，26,479,041 bytes；SHA-256 为 `45C3AC59CB541BE496CC85715A5D8342744308A667019F2EBD3F941D92E7E283`；包名为 `com.maxzrb.piliexo`，versionCode 为 3。
- v26.8.28.2 arm64 正式 Release APK：`dist/PiliExo_android_v26.8.28.2_arm64-v8a.apk`，26,603,631 bytes；SHA-256 为 `05E64EB063878F55DEE512B533BEB2BE1CCC6A39DC9CBB35A163DCA7A1FA027E`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- v26.8.28.2 v7a 正式 Release APK：`dist/PiliExo_android_v26.8.28.2_armeabi-v7a.apk`，26,479,433 bytes；SHA-256 为 `05674F4765F134944B4E1B1DA3B63B192C2D85C025808D1BCBAFBC9E499EB0D1`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- GitHub `v26.8.28.2` Release 资产状态为 `uploaded`；ModelScope `resolve/master/releases/v26.8.28.2/...apk` 两个地址实测 HTTP 200。
- `v26.8.29.1` 已用正式签名重新构建并覆盖 Release 资产；arm64 为 27,003,414 bytes、SHA-256 `BE8198C3B071EDF7A8E25E9E872996BDCEAA6F9066DFF37EED88F53722B67166`，v7a 为 26,869,934 bytes、SHA-256 `07A58BBBA2B9D557C375E80B6D21A14DF4ADC3195E7FEF25D8E72AC7C98804E4`。
- 正式签名版已通过 `aapt2` 核验 `com.maxzrb.piliexo`、`versionName=26.8.29`、`versionCode=1`、对应 ABI 和 `libffmpegJNI.so`；`apksigner` V2 验证通过，证书 DN 为 `CN=PiliExo, O=AerithDream, C=CN`，证书 SHA-256 为 `43f72e53fa2eaf3bb6a689573659217064df8066a1987822d94c7f109fa0e982`，RSA 4096 位。
- `v26.8.29.1` ModelScope 两个地址已用正式签名版覆盖，均返回 HTTP 200，`X-Linked-ETag` 与上述新 APK SHA-256 一致；GitHub Release 说明已同步更新。

## 当前限制

- 完整 `flutter analyze --no-pub` 报告 42 条 info/lint，无 error；包含项目既有弃用提示和新增 HDR 文件的风格提示。
- 本机已准备并验证打补丁的 Flutter 3.47.2 SDK；当前发布包为 `v26.8.29.3`，后续构建应继续通过工具链校验脚本。
- 设备端安装权限确认仍由用户自行处理；代理未再次安装或启动 APK。
- 当前环境没有本轮 HDR/振动真机验收，SurfaceFlinger dataspace、HDR 屏幕模式、首帧、震动振幅、磨砂效果和长时间音画同步仍需实测。
- 当前正式密钥只保存在本机并被 Git 忽略；必须备份 `android/piliexo-release.jks`、`android/key.properties` 和密码。正式签名版替换了此前 Debug 签名的同版本资产，旧 Debug 包不能覆盖安装，首次迁移需卸载后安装。
- 正式版本现为 `v26.8.29.3` / `26.8.29+3`；后续测试包继续沿用该版本号，下一次正式发布按发布日期和当天正式发布次数重新计算。

## 下一步

- 用户自行按设备 ABI 安装正式签名版 `v26.8.29.3` APK；若设备已有被覆盖前的 Debug 签名包，先卸载旧包再安装。随后验收默认震动、滑块即时反馈、磨砂开关与三档效果、HDR10、Dolby Vision、HDR Vivid、横竖屏、前后台、画中画、拖动、字幕和 30 分钟连续播放。
- 复测 SDR↔HDR 切换红屏和返回播放列表残帧；确认无残留后再按 Release 标签继续迭代。
- 重点验收状态栏跟随视频模糊的边界、HDR PixelCopy 兼容性、暂停/播放更新节奏，以及播放器洞察实际解码器和色彩信息。
- 同时验收中部上下滑全屏震动、设置页三档洞察模式、智能档起播/掉帧提示与控制条覆盖关闭语义，以及“更多设置”中的手动详情入口。

### 2026-08-28 20:06 (+08:00)

- 根据用户截图确认顶栏与状态栏之间的视觉缝隙来自顶栏顶部边框；已将顶栏边框关闭，并将轻薄磨砂档透明度调为 0.64，使背景透出更多。
- 修正震动设置 `SwitchModel` 的默认值为开启，解决新安装或无历史设置时界面开关显示为关闭的问题；已有明确关闭值不被覆盖。
- 新增 `docs/发布流程.md`，明确测试阶段保持 `26.8.28+3` 不变，只有正式发布时推进版本号、生成 `vYY.M.D.N` 标签并填写 `[新增]`、`[更改]`、`[修复]`、`[同步]` 发布说明。
- 使用同一版本号重新构建并核验 v26.8.28.3 双 ABI APK：arm64 为 26,604,031 bytes，SHA-256 `426BE600CCA5AD02C740063BE2315984ED74C178A6665AAE580A963AA108A1A8`；v7a 为 26,479,661 bytes，SHA-256 `8590D4F9A77C13EBB5ED77B7CA6B68904DC3E1ACAD8A7DCEFDCAEF40C4947431`。
- `flutter test --no-pub` 8/8 通过，`flutter analyze --no-pub` 无 error/warning（42 条 info），Android 单测和 Gradle Release 构建通过；本轮未通过 ADB 安装或启动，v26.8.28.3 尚未发布。

### 2026-08-28 20:39 (+08:00)

- 根据用户反馈移除主底栏和浮动底栏 `FrostedSurface` 的顶部边框，磨砂材质保留，避免底栏上沿出现突兀亮线。
- 用户提供 `D:\read\gradle-9.5.0-all.zip` 后，已复制到 Gradle wrapper 标准缓存并确认 `Gradle 9.5.0` 可用；该缓存可供其它使用同一分发包的项目复用。
- Flutter 分包命令因插件 Kotlin 增量缓存跨 C/D 盘符失败；改用 `kotlin.incremental=false` 和 `split-per-abi=true` 的 Gradle 9.5 任务后构建成功。
- 测试版本继续保持 `26.8.28+3`，未递增版本号。v26.8.28.3 双 ABI APK 已重新核验：arm64 为 26,603,903 bytes，SHA-256 `2B13DAA38924C02708549A61F09AFF7AA2844425AD8BC79C994D6E9DE390E686`；v7a 为 26,479,041 bytes，SHA-256 `45C3AC59CB541BE496CC85715A5D8342744308A667019F2EBD3F941D92E7E283`。
- `flutter test --no-pub` 8/8 通过，Gradle 9.5 Release 分包构建成功；未通过 ADB 安装或启动，v26.8.28.3 尚未发布。

## Session Log

### 2026-08-28 16:22 (+08:00)

- 应用项目 Flutter 补丁脚本并恢复损坏的 `flutter_inappwebview_android` Git 缓存文件后，Android debug APK 构建成功。
- 用户设备 `AN5UUT6225004417`（HONOR MEP-AN00，Android 16）在线；ADB `install -r -d` 和 shell 安装均返回 `INSTALL_FAILED_ABORTED: User rejected permissions`，判断为设备端安装授权未确认。
- 用户明确要求仅提供安装命令，不再由代理发起安装操作。

### 2026-08-28 16:53 (+08:00)

- 从设备 `/sdcard/Pictures/Screenshots/Screenshot_20260828_163030_com_example_piliplus_debug_MainActivity.jpg` 拉取并检查用户截图；红屏文本为 Flutter `setState() or markNeedsBuild() called during build`，涉及 `Obx`。
- 修复 `lib/plugin/pl_player/view/view.dart`：HDR 切换时的变换矩阵、还原按钮和原生画面模式同步改为 post-frame 执行，避免构建期间触发响应式更新。
- 修复 `lib/plugin/pl_player/backends/media3_hdr.dart`、`lib/plugin/pl_player/controller.dart` 与 `android/app/src/main/kotlin/com/example/piliplus/HdrMedia3Plugin.kt`：SurfaceView 脱离时先隐藏并清空视频 Surface，重新挂载时恢复可见，释放 HDR 后端前也执行清屏。
- 验证：全量 `flutter test`、定向 Flutter analyze（仅 lint/info）、Android 原生编译和 `:app:testDebugUnitTest -Pkotlin.incremental=false` 均通过。
- Git：仍处于 `feature/android-media3-hdr`，工作树包含本功能尚未提交的实现及记录文件；未创建提交。

### 2026-08-28 17:11 (+08:00)

- 从设备拉取并检查最新截图 `/sdcard/Pictures/Screenshots/Screenshot_20260828_165636_com_example_piliplus_debug_MainActivity.jpg`；确认残留的是整块独立 `SurfaceView`，覆盖在 HDR 播放列表页面上，而非播放器内部单帧残留。
- 修复 `lib/pages/video/view.dart` 和 `lib/plugin/pl_player/controller.dart`：Media3 HDR 播放时将路由返回拦截为手动返回，离开前立即发起 Surface 隐藏；首页返回和系统返回均覆盖，SDR 保持原有 `canPop` 行为。
- 修复 `HdrMedia3Plugin.kt`：隐藏时使用 `View.GONE`、清空视频 Surface 并将透明度置零，重新 attach 时恢复可见性与透明度。
- 验证：全量 `flutter test` 通过，目标文件定向 `flutter analyze` 无 error（仅 8 条既有 info），Android `:app:testDebugUnitTest -Pkotlin.incremental=false` 和 `:app:assembleDebug -Pkotlin.incremental=false` 通过。
- 新 APK：`build/app/outputs/flutter-apk/app-debug.apk`，201236035 bytes，SHA-256 `ABCC62569508456C5B7872AB725F611BBF227B88B5AE5FDE95E9E3A9A44BCBDC`；未通过 ADB 安装或启动，仍由用户自行安装验证。

### 2026-08-28 18:18 (+08:00)

- 新增 `HapticFeedbackPlugin`，所有底栏和侧栏导航通过 `MainController.setIndex` 触发，Android 使用 `VibrationEffect` 振幅 1–255；保留震动开关并新增强度设置。
- 应用改名为 PiliExo，说明定位为 fork 自 PiliPlus 的 Android HDR 第三方自用修改版；更新比较改用 GitHub Release 标签，Android 下载 ModelScope 优先、GitHub 兜底。
- GitHub fork、ModelScope 数据集和 `v26.8.28.1` Release 已创建并验证；Release 资产与镜像文件 SHA-256 均为 `9D64CAD5C991485E4DCB323C2DAA8FA2DC5F8B300C97EA7DD8C71190B2D5664F`。
- 保留 GitHub fork 创建时带入的上游 Flutter 3.47.2、主题、自定义字体和依赖更新，并在 `[同步]` 版本记录中标注。
- 验证：`flutter test --no-pub` 5/5 通过；`flutter analyze --no-pub` 无 error；Android `:app:testDebugUnitTest` 和 release 构建通过。未通过 ADB 安装或启动。

### 2026-08-28 18:58 (+08:00)

- 新安装默认开启震动并将默认振幅设为 80；新增滑块拖动即时反馈，取消对话框时恢复原值。
- 两个普通视频画质列表调整为 8K、HDR Vivid、杜比视界、HDR 真彩优先；“蜂窝网络”设置文案改为“移动数据”。
- 顶栏、底栏、普通页面 AppBar 和浮动底栏加入磨砂半透明背景；HDR 视频仍使用原生 `SurfaceView`，未引入 `SurfaceTexture`。
- Android 应用标识切换为 `com.maxzrb.piliexo`，Release 开启 R8/资源压缩并仅构建 `arm64-v8a`、`armeabi-v7a`；更新器按 `supportedAbis` 选择匹配资产，找不到时只回退通用 APK。
- 关于页描述精简为“支持HDR的PiliPlus修改版”；修正透明 NavigationBar 主题下浮动底栏的磨砂底色。
- 验证：`flutter test --no-pub` 8/8 通过；`flutter analyze --no-pub` 无 error；Android `:app:testDebugUnitTest -Pkotlin.incremental=false` 通过；Gradle Release 构建通过；`git diff --check` 通过。
- 成品：`dist/PiliExo_android_v26.8.28.2_arm64-v8a.apk`（26,601,707 bytes，SHA-256 `94EA78F3AA2458B9C56F264ED8A99BAF8971AD0390B010FABFD7C558C6B371A6`）和 `dist/PiliExo_android_v26.8.28.2_armeabi-v7a.apk`（26,480,705 bytes，SHA-256 `E9234886FC779CBC424A8B6965AB256353753549FFE973EDEBAA8C18EE4B196C`）；aapt 已核验包名、版本号和 native ABI。
- 本地没有 `android/key.properties`，所以本次构建使用 debug keystore 兜底签名，未上传为正式 Release。
- 未通过 ADB 安装或启动；当前改动仍在 `feature/android-media3-hdr` 工作树中，尚未提交或发布 v26.8.28.2。

### 2026-08-28 19:49 (+08:00)

- 新增外观设置“磨砂半透明”开关，默认开启；新增“轻薄 / 标准 / 浓厚”三档，分别调整模糊半径和透明度，切换即时生效。
- `FrostedSurface` 增加全局配置监听，主页顶栏、主底栏、浮动底栏、普通 `SimpleScaffold` AppBar，以及动态/WebView/日志特殊顶栏统一响应设置；关闭后不使用 `BackdropFilter` 并恢复不透明背景。
- 应用描述保持为“支持HDR的PiliPlus修改版”；修复透明 NavigationBar 主题下浮动底栏无底色的问题。
- 版本递增为 `v26.8.28.3`；`flutter test --no-pub` 8/8 通过，`flutter analyze --no-pub` 无 error/warning（42 条 info），Android `:app:testDebugUnitTest -Pkotlin.incremental=false` 通过，Gradle Release 构建通过，`git diff --check` 通过。
- 成品：`dist/PiliExo_android_v26.8.28.3_arm64-v8a.apk`（26,604,087 bytes，SHA-256 `2B2DEFDF6B4A8239CB0288CCFD9212279B41C256B5E719DA26FF6C06D05B01E1`）和 `dist/PiliExo_android_v26.8.28.3_armeabi-v7a.apk`（26,479,865 bytes，SHA-256 `F9E46227B2ED70E07BE03614524B0C981D8EB0160376244367A2FF763C849E9A`）；aapt 已核验包名、versionCode 和 native ABI。
- 未通过 ADB 安装或启动；当前改动仍在 `feature/android-media3-hdr` 工作树中，尚未提交或发布 v26.8.28.3。

### 2026-08-28 21:11 (+08:00)

- 按用户确认的版本规则，正式发布编号取远端最新 Release 的 N+1；远端最新 `v26.8.28.1`，本次发布 `v26.8.28.2`，测试包不占用编号。
- 提交 `1669ff368df0c12a72e92fe409c3b84737c925d5` 已推送到 `maxzrb/PiliExo` 的 `main`，标签 `v26.8.28.2` 已推送；GitHub Release 已创建并上传两个 ABI 资产。
- ModelScope `AerithDream/PiliExo` 已上传 `releases/v26.8.28.2/` 下的 arm64 与 v7a 资产，两个镜像地址均实测 HTTP 200。
- 正式 APK 哈希：arm64 `05E64EB063878F55DEE512B533BEB2BE1CCC6A39DC9CBB35A163DCA7A1FA027E`（26,603,631 bytes）；v7a `05674F4765F134944B4E1B1DA3B63B192C2D85C025808D1BCBAFBC9E499EB0D1`（26,479,433 bytes）。
- `flutter test --no-pub` 8/8、Gradle 9.5 Release 分包构建、aapt 包名/版本/ABI 核验通过；未通过 ADB 安装或启动。由于没有 `android/key.properties`，本次 APK 使用 debug keystore 兜底签名。

### 2026-08-28 23:07 (+08:00)

- 版本纠正：远端最新正式标签和 Release 仍为 `v26.8.28.2`；此前 `v26.8.28.3` 双 ABI 文件是测试构建，没有对应远端标签或 Release。`pubspec.yaml`、Dart 默认发布元数据和本机 `android/local.properties` 已恢复到 `26.8.28+2`，后续测试不得递增版本号。
- 同步上游 3 个提交：`37ae9cf2d` → `5935b03c1`、`4da811080` → `032847b1b`、`9058ac144` → `b4bed5166`；未直接合并上游主线，保留 PiliExo 的 Android HDR 改动。
- Android 新增仓库内 FFmpeg 音频扩展 AAR，基于 AndroidX Media 1.11.0 `decoder_ffmpeg` 与 FFmpeg 6.0，启用 AC-3、E-AC-3/E-AC-3-JOC 核心和 TrueHD，硬件优先、软件回退；仅包含 arm64-v8a/armeabi-v7a。
- Android 单测与 Gradle 9.5 R8 release 分 ABI 构建通过。新测试产物位于 `build/app/outputs/flutter-apk/`：arm64 `26,919,958` bytes，v7a `26,791,586` bytes；aapt 已核验包名 `com.maxzrb.piliexo`、versionName `26.8.28`、versionCode `2` 和单一对应 ABI，APK 内含 `libffmpegJNI.so`。
- 说明文案已统一为“支持HDR的PiliPlus修改版”；发布流程补充了 SNAPSHOT/本地版本覆盖排错、测试版本冻结和 FFmpeg AAR 验收要求。
- 本轮未创建或推送新标签、GitHub Release、ModelScope 资产；状态栏跟随视频模糊/变色与播放洞察按用户计划留待后续。
- 功能源码与 AAR 已提交为 `035314a79`（`fix: restore test version metadata and add Dolby fallback`）；本次最终交接记录补充提交为 `dbfbb1ecf`，本地 `pili_release.json` 已刷新到功能提交。

### 2026-08-29 00:09 (+08:00)

- 根据用户澄清，确认需求是“手机顶部系统状态栏跟随视频的模糊背景”，不是播放器画面或视频转场模糊；已参考 BiliPai 的 `PixelCopy`/低分辨率环境帧/约 66ms 采样实现落地。
- Android HDR 使用 Media3 `SurfaceView` 的 `PixelCopy` 读取 96×54 当前帧；SDR 使用现有 Flutter 视频区域的低分辨率 RepaintBoundary 采样；两条链路都只绘制到状态栏 inset，播放画面不变。
- 新增“播放器洞察”面板，按 BiliPai 的信息组织方式展示概览、视频、音频、播放和事件，并接入 Media3 HDR 与 mpv 已报告数据。
- 验证通过：`flutter test --no-pub` 8/8、`flutter analyze --no-pub` 无 error（42 条 info）、Android Kotlin 编译/单测、Gradle 9.5 R8 分 ABI Release 构建和 `aapt2` 包名/版本/ABI 核验；本轮未安装或启动 ADB，未创建新标签或 Release，版本保持 `26.8.28+2`。

### 2026-08-29 00:35 (+08:00)

- 中部播放器上滑/下滑全屏手势在越过阈值、实际调用全屏切换时加入统一振幅震动反馈；其它全屏入口行为不变。
- 修正播放器洞察入口：视频页“更多设置”不再等待 Media3/mpv 实例条件，固定在菜单靠前位置显示；设置页播放器设置说明同步加入“洞察”。
- 参考 BiliPai 的 `ALWAYS / ATTENTION / OFF` 洞察组织方式，新增 PiliExo 的“显示 / 智能 / 不显示”设置；智能模式按用户要求改为仅对新增掉帧显示 5 秒，再以 350ms 渐隐消失，重新掉帧重新计时；默认智能。
- 新增 `PlaybackInsightHud`，摘要可点击打开完整详情；关闭自动摘要不影响视频页手动打开详情。
- 验证通过：`flutter test --no-pub` 8/8、`flutter analyze --no-pub` 无 error（42 条 info）、Gradle 9.5 R8 双 ABI Release 构建、`aapt2` 包名/版本/ABI 核验；测试版本保持 `26.8.28+2`，未安装或启动 ADB，未创建新标签或 Release。
- 当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪；本轮功能改动已提交。

### 2026-08-29 00:57 (+08:00)

- 参考 BiliPai 的同层交互，将 `PlaybackInsightHud` 从右上角摘要改为可点击的播放器内联详情展开；展开时显示半透明遮罩，点击遮罩、关闭图标或关闭按钮均可收起，摘要点击不再调用二级 `showDialog`。
- 洞察摘要位置下移并增加右侧内缩；详情面板按播放器实际尺寸自适应，横屏最大宽度约为可用宽度的 42%、最大高度 360，竖屏最大高度 520。
- 将 `PlaybackInsightHud` 放到播放器控件绘制层之后，保证展开面板能够覆盖同层控制条并接收点击；保留视频页“更多设置 → 播放器洞察”的手动对话框入口。
- 测试版本继续保持 `26.8.28+2`，未创建标签或 Release。`flutter test --no-pub` 8/8、Gradle 9.5 双 ABI Release、`aapt2` 包名/版本/ABI 核验通过；未通过 ADB 安装或启动。
- 当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 01:09 (+08:00)

- 重新核对 BiliPai `VideoPlayerOverlay.kt`：洞察点击通过 `showInsightDetails` 切换同层状态，使用播放器范围的半透明黑色遮罩拦截背景点击，详情内容由 Overlay 中的 surface 承载；不使用 Dialog。
- 修正 PiliExo：删除独立右侧 `Material` 详情卡片，改为同一个黑色半透明洞察 surface 从摘要态扩展为覆盖播放器主要区域的详情态，详情直接显示五组诊断数据；遮罩、关闭图标和关闭按钮可收起。
- 智能模式增加起播窗口：首次获得有效播放器数据时显示 5 秒，后续新增掉帧继续显示 5 秒并重新计时；无数据时会重置起播状态，避免下一段视频不再提示。
- 测试版本继续保持 `26.8.28+2`，未创建标签或 Release。`flutter test --no-pub` 8/8、Flutter analyze 无 error、Gradle 9.5 双 ABI Release、`aapt2` 包名/版本/ABI 核验通过；未通过 ADB 安装或启动。
- 当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 01:19 (+08:00)

- 智能播放器洞察新增 `PlPlayerController.showControls` 监听：控制条/进度条呼出时主动显示洞察摘要，控制条自动隐藏或手动关闭时立即取消计时、隐藏摘要并收起详情。
- 起播 5 秒和新增掉帧 5 秒逻辑继续保留；当控制条处于显示状态时洞察不被计时器提前隐藏，控制条关闭后按用户要求同步隐藏。
- 测试版本继续保持 `26.8.28+2`，未创建标签或 Release。`flutter test --no-pub` 8/8、`flutter analyze --no-pub` 无 error、Gradle 9.5 双 ABI Release、`aapt2` 包名/版本/ABI 核验通过；未通过 ADB 安装或启动。
- 当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 01:28 (+08:00)

- 根据用户反馈修正智能模式的可见性边界：控制条/进度条呼出时主动显示，收起时只清除控制条触发的显示并收起由控制条打开的详情；起播和新增掉帧触发的 5 秒事件窗口不被控制条收起取消，因此即使控制条已经隐藏，提示仍能正常出现。
- 测试版本仍为 `26.8.28+2`，未创建新标签或 Release。`flutter test --no-pub` 8/8、`flutter analyze --no-pub` 无 error（42 条既有 info）、Gradle 9.5 双 ABI Release 和 `aapt2` 包信息核验通过；未通过 ADB 安装或启动。
- 当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 01:34 (+08:00)

- 根据用户进一步澄清调整智能模式：未呼出控制条时，起播和新增掉帧事件独立显示 5 秒；控制条呼出后由控制条状态优先接管并覆盖当前事件窗口，控制条关闭时同步关闭洞察、收起详情并取消这次已被覆盖的事件窗口，避免自动提示继续遮挡重要画面。
- 检查 PiliPlus 上游 `main` 至 `9058ac144`：`37ae9cf2d`、`4da811080`、`9058ac144` 三个提交在本地已有等价 cherry-pick（分别为 `5935b03c1`、`032847b1b`、`b4bed5166`），没有新的上游提交需要合并。
- 测试版本仍为 `26.8.28+2`，本轮尚未重新构建新增逻辑，未创建新标签或 Release；当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 01:38 (+08:00)

- 完成智能洞察最终交互：未呼出控制条时，起播/掉帧事件各自显示 5 秒；控制条呼出后优先接管并覆盖当前事件窗口，控制条关闭时同步关闭洞察、收起详情并取消这次已被覆盖的事件窗口，避免重要画面继续被遮挡。
- 全屏洞察摘要再向左移动 12dp，右侧内缩从 24dp 调整为 36dp；普通窗口位置不变。
- 复查 PiliPlus 上游 `main` 至 `9058ac144`：三个上游提交均已在本地以等价 cherry-pick 存在，没有新的独有提交需要合并。
- 测试版本仍为 `26.8.28+2`，未创建新标签或 Release。Flutter 单测 8/8、Flutter analyze 无 error（42 条既有 info）、Gradle 9.5 双 ABI Release 和 `aapt2` 核验通过；未通过 ADB 安装或启动。
- 当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 01:58 (+08:00)

- 按日期版本规则完成正式发布：远端最新 `v26.8.28.2`，本次发布日期为 2026-08-29，因此发布 `v26.8.29.1`，应用版本 `26.8.29+1`；发布提交为 `e29dc3dc987248e6cee5a6d4acd13cd656d98bbc`。
- GitHub Release：<https://github.com/maxzrb/PiliExo/releases/tag/v26.8.29.1>；两个资产状态均为 `uploaded`，arm64 SHA-256 `65845C055CA83D7354AA498B0E567F457BEB91AFC1AABC43BAD453BAEDFD8324`，v7a SHA-256 `97C08218F9C257F473E04FD2E773F02D2FD65D551E9588338074A7EEBBCACF40`。
- ModelScope 镜像已上传并实测可访问：<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.1/PiliExo_android_v26.8.29.1_arm64-v8a.apk>、<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.1/PiliExo_android_v26.8.29.1_armeabi-v7a.apk>；HTTP 200、Content-Length 正确，`X-Linked-ETag` 与本地 SHA-256 一致。
- `flutter test --no-pub` 8/8、Android `:app:testDebugUnitTest -Pkotlin.incremental=false`、Gradle 9.5 双 ABI Release 和 `aapt2` 核验通过；`flutter analyze --no-pub` 无 error，仅有项目既有 42 条 info。
- 因没有 `android/key.properties`，本次 APK 使用本机 Android Debug keystore；与上一正式包证书一致，可覆盖更新，但后续应配置固定正式签名，避免 keystore 丢失或切换密钥导致无法升级。
- 版本记录、Release Note 和发布流程已同步更新；当前测试包继续保持 `26.8.29+1`，当前工作树保留用户截图 `tmp/latest_frosted_gap.jpg` 未跟踪。

### 2026-08-29 02:08 (+08:00)

- 生成固定正式签名 `android/piliexo-release.jks`：PKCS12、RSA 4096、有效期 10000 天；`android/key.properties` 接入 Gradle，实际密钥与密码均未纳入 Git。
- 用正式签名重建 `v26.8.29.1` 双 ABI APK：arm64 `27,003,414` bytes，SHA-256 `BE8198C3B071EDF7A8E25E9E872996BDCEAA6F9066DFF37EED88F53722B67166`；v7a `26,869,934` bytes，SHA-256 `07A58BBBA2B9D557C375E80B6D21A14DF4ADC3195E7FEF25D8E72AC7C98804E4`。
- `aapt2`、`apksigner`、Gradle 9.5 核验通过；正式证书 SHA-256 为 `43f72e53fa2eaf3bb6a689573659217064df8066a1987822d94c7f109fa0e982`。
- 已原地覆盖 GitHub Release 和 ModelScope 两个 ABI 资产，并把签名迁移说明写入 `version/release-notes-v26.8.29.1.md`；同版本的旧 Debug 包需卸载一次，后续版本使用同一正式密钥即可覆盖更新。

### 2026-08-29 11:01 (+08:00)

- 根据用户反馈修复播放器洞察详情被隐藏逻辑收起的问题：智能模式下控制条显示状态变化不再关闭已打开的详情，仅清理自动摘要窗口。
- 调整全屏详情面板：沿用摘要的实际宽度、右侧位置和顶部位置，仅增加纵向高度，并限制在播放器可用高度内；普通窗口布局保持不变。
- 修改文件：`lib/plugin/pl_player/widgets/playback_insight.dart`。
- 验证：目标文件 `flutter analyze --no-pub` 无问题；`flutter test --no-pub` 8/8 通过；`git diff --check` 通过；未生成 APK，未进行真机验收。
- 环境：系统 PATH 未提供 `dart`/`flutter`，本轮使用 `C:\Users\maxzr\AppData\Local\Temp\flutter-3.47.1-sdk\flutter\bin\` 下的 SDK，并继续使用 `--no-pub`；`git pull --ff-only` 因当前分支未设置上游而未同步。
- Git：工作区保留用户未跟踪目录 `tmp/`；本轮新增播放器洞察源码改动及 HandShake 记录改动，尚未提交。

### 2026-08-29 11:13 (+08:00)

- 根据用户反馈，为底栏首页/动态刷新接入现有下拉刷新动画：点击当前导航项触发刷新时，通过对应 `RefreshIndicatorState.show()` 显示动画，再执行原有网络刷新回调。
- 首页推荐、热门、分区、直播、番剧、影视 tab，以及动态各 tab 均绑定独立刷新 key；手动下拉刷新逻辑保持不变，滚动未到顶部时仍只执行回到顶部。
- 修改文件：`lib/pages/common/common_controller.dart`、`lib/pages/main/controller.dart`、`lib/pages/home/controller.dart`、`lib/pages/rank/controller.dart`、`lib/pages/dynamics/controller.dart`，以及首页/动态刷新视图文件。
- 验证：11 个相关 Dart 文件 `flutter analyze --no-pub` 无问题；`flutter test --no-pub` 8/8 通过；`git diff --check` 通过；未生成 APK，未进行真机验收。
- Git：继续保留上一轮播放器洞察改动、本轮刷新动画改动及用户未跟踪目录 `tmp/`，尚未提交。

### 2026-08-29 11:30 (+08:00)

- 根据用户反馈补齐播放器洞察“视频”详情分组中的“视频码率”；视频/音频码率均继续使用播放器已采集的数据，不新增推测值。
- 新增 `test/plugin/pl_player/playback_insight_test.dart` 回归测试，确认视频码率和音频码率分别出现在对应详情分组。
- 验证：相关文件 `flutter analyze --no-pub` 无问题；`flutter test --no-pub` 9/9 通过；`git diff --check` 通过；未生成 APK，未进行真机验收。
- Git：工作区继续保留上一轮播放器洞察/底栏刷新改动和用户未跟踪目录 `tmp/`，本轮码率修复尚未提交。

### 2026-08-29 12:06 (+08:00)

- 按正式发布流程将播放器洞察和底栏刷新动画修复发布为 `v26.8.29.2`，应用版本 `26.8.29+2`；版本提交 `68b9a377f9dc13aabd99d265e67bcaec81f11207` 已推送至 fork `main`，并创建正式标签。
- GitHub Release 已发布：<https://github.com/maxzrb/PiliExo/releases/tag/v26.8.29.2>；两个 APK 资产均为 `uploaded`。ModelScope 数据集 `AerithDream/PiliExo` 已上传至 `releases/v26.8.29.2/` 对应目录。
- arm64 APK `25,681,072` bytes，SHA-256 `E3988B841C173F8D3D2595299A639FC2EE2C1541CE1F80665832F3FB0A83BF92`；armeabi-v7a APK `25,550,590` bytes，SHA-256 `D0876E6967C7DC5F182925E8083C4B5F2E62E0A92E1500715C018904489556E1`。
- 发布验证通过：`flutter test --no-pub` 10/10；定向 Dart analyze 无问题；`aapt2` 包名/版本/ABI/`libffmpegJNI.so` 核验通过；`apksigner` V2 正式签名核验通过；ModelScope 回读文件 SHA-256 与本地一致；`git diff --check` 通过。
- 构建环境使用本机 Flutter 3.47.1（项目声明 3.47.2），构建时以 `kotlin.incremental=false` 规避跨盘 Kotlin 缓存问题，并预下载且 MD5 校验媒体库依赖；未进行 ADB 真机安装或启动验收。
- 当前工作树仍保留用户未跟踪目录 `tmp/`，未提交发布产物目录和 `pili_release.json` 等忽略文件。

### 2026-08-29 12:49 (+08:00)

- 根据用户反馈再次修复播放器洞察视频码率：普通网络源、Media3 HDR 源和 HDR 失败回退均保存 DASH 视频/音频轨道码率；播放器实时快照在原生轨道未返回码率时使用数据源回退值，概览和“视频”分组均可显示“视频码率”。
- 按 BiliPai 的全屏覆盖层策略重做洞察全屏尺寸：摘要按屏幕宽度分档使用顶部/右侧内边距、48dp 最小高度和 12–14sp 字体；详情位于右侧、宽度约为播放器 42%（320–440dp）、最大高度 360dp，并在可用区域垂直居中；普通窗口不变。
- 检查更新的 Android 路径接入官方 Aria2-next 2.6.7 ARM64 二进制，启用 `--split=32`、`--max-connection-per-server=32`、断点续传、完整性和 Release SHA-256 校验；下载成功后通过 FileProvider 自动唤起系统安装器。非 ARM64 或 Aria2-next 不可用时保留应用内 HTTP 下载回退。
- 新增 FileProvider 配置、`REQUEST_INSTALL_PACKAGES` 权限、Aria2-next 许可证说明和 Android 更新 MethodChannel；Android 标准安装仍由系统显示确认，应用不会静默确认安装。
- 验证：`flutter test --no-pub` 11/11 通过；相关 Dart 文件 `flutter analyze --no-pub --no-fatal-infos` 无 error，仅有控制器原有 4 条 info；Android `:app:compileDebugKotlin -Pkotlin.incremental=false` 和 `assembleDebug -Pkotlin.incremental=false` 通过；APK 已核验更新权限、FileProvider、Aria2-next 资源；`git diff --check` 通过。
- 当前版本仍为 `26.8.29+2`，本轮未递增版本号、未创建新 Release；未进行 ADB 真机安装或启动验收。工作区继续保留用户未跟踪目录 `tmp/`，功能源码及记录尚未提交。

### 2026-08-29 13:24 (+08:00)

- 统一编译工具链：本机准备并验证 Flutter `3.47.2` SDK；`.fvmrc`、`pubspec.yaml`、`pubspec.lock` 和实际 SDK 均通过 `lib/scripts/verify_flutter.ps1` 校验，5 个 GitHub Actions 工作流改为从 `.fvmrc` 读取版本并在构建前校验。
- 修复 Android/Kotlin 增量缓存跨盘问题：`android/gradle.properties` 固定 `kotlin.incremental=false`，本地和 CI 不再需要追加 `-Pkotlin.incremental=false`；保留 `android.builtInKotlin=false`、`android.newDsl=false`，因为当前 Flutter Gradle 插件与 AGP 9 新 DSL 直接组合会触发类型冲突。
- 发布流程文档已补充固定工具链校验、跨盘构建约束和标准检查命令；本轮不递增 `26.8.29+2`，未创建新 Release。
- 验证通过：Flutter 工具链校验、`flutter test --no-pub` 11/11、全量 `flutter analyze --no-pub --no-fatal-infos` 无 error、默认 `android\gradlew.bat :app:compileDebugKotlin --console=plain`、标准 `flutter build apk --debug --no-pub` 和 `git diff --check`。
- Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，208,644,128 bytes，SHA-256 `EC4C6A6DAD3FDC5640E57F0E11A1229A38D96AAC707A1F4AB54EFE5F2793E3F7`；已核验包含 Aria2-next ARM64 资源、许可证说明和 FileProvider。
- 标准 ARM 双 ABI Release 构建成功：arm64 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`（31,662,862 bytes，SHA-256 `72E7F5FE88BAFA2CD07EE83D6CDE30B49FD6556607590753FBF70BD6F72E21BA`），v7a `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`（31,536,514 bytes，SHA-256 `923102E4C35B626B0B9F5C5448274506B436D6AAE927CEAE2DFA9EB6F201D5D9`）；`aapt2` 核验包名 `com.maxzrb.piliexo`、`versionName=26.8.29`、`versionCode=2` 和对应 ABI，`apksigner` V2 验证通过。
- 当前工作区保留用户未跟踪目录 `tmp/`，本轮源码、工作流和记录改动尚未提交；未进行 ADB 真机安装或启动验收。

### 2026-08-29 13:53 (+08:00)

- 按同日正式发布规则将版本递增为 `v26.8.29.3`，应用版本为 `26.8.29+3`；发布提交 `4b3baa808180c40c6857b71f0701ee70e4bc3ec5` 已推送至 `maxzrb/PiliExo` 的 `main`，并创建、推送带注释标签。
- GitHub Release 已发布：<https://github.com/maxzrb/PiliExo/releases/tag/v26.8.29.3>；arm64 与 armeabi-v7a 两个资产状态均为 `uploaded`。
- ModelScope `AerithDream/PiliExo` 已同步：<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.3/PiliExo_android_v26.8.29.3_arm64-v8a.apk>、<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.3/PiliExo_android_v26.8.29.3_armeabi-v7a.apk>；两个地址 HTTP 200，`X-Linked-ETag` 与本地 SHA-256 一致。
- arm64 APK：31,663,011 bytes，SHA-256 `F127645D45EB69E74616FFD4937BA9A9D2EFD819842CA1FE4C066B3770B71224`；armeabi-v7a APK：31,536,321 bytes，SHA-256 `D9D871CC1C7F0C6EB6E0ABC42ABE301F6C5FDB7CCF818B1B65F7FA3D58136565`。两个包均通过 `aapt2` 和 `apksigner` V2 核验。
- 本轮发布前已通过 Flutter 3.47.2 工具链校验、`flutter pub get`、`flutter test --no-pub` 11/11、全量 analyze 无 error、标准 ARM 双 ABI Release 构建和 `git diff --check`。
- 当前工作树仅保留用户未跟踪目录 `tmp/`；本次发布后的 HandShake 收尾记录已写入，准备提交，不修改或提交该目录。

### 2026-08-29 14:06 (+08:00)

- 根据用户反馈修正播放时画质/音质切换：删除播放器底栏和视频页顶部控件对四个默认画质/音质配置键的回写，仅保留当前播放器的画质、音质和播放位置切换。
- 设置页“默认画质”“移动数据画质”“默认音质”“移动数据音质”的手动保存逻辑保持不变；`播放器设置仅对当前生效` 仍继续控制其它播放器设置。
- 修改文件：`lib/plugin/pl_player/view/view.dart`、`lib/pages/video/widgets/header_control.dart`。
- 验证通过：两个目标文件 Flutter analyze 无问题，`flutter test --no-pub` 11/11 通过，`git diff --check` 通过；本轮未打包、未创建新 Release。
- 当前版本仍为 `v26.8.29.3` / `26.8.29+3`；工作区保留用户未跟踪目录 `tmp/`，本轮代码与记录改动尚未提交。

## 2026-08-29 16:48

- 根据设备崩溃日志定位并修复液态玻璃的实际 Java 异常：ComposeView 挂载到 FlutterView 时找不到 `ViewTreeLifecycleOwner`，此前会在 Flutter 平台视图 JNI 检查处升级为 SIGABRT；现在由 `LiquidGlassViewTree` 在 Activity decor 根视图和 ComposeView 挂载前绑定 FlutterActivity 生命周期，宿主不兼容时创建透明回退视图。
- 补充 `androidx.lifecycle:lifecycle-runtime-android:2.9.4` 依赖，并继续保留 TLHC/Virtual Display 回退、SurfaceView 局部 PixelCopy、原生异常兜底和液态玻璃安全版本探测。
- 验证通过：Flutter 全量测试 14/14、液态玻璃定向 analyze、Android `:app:testDebugUnitTest`、Kotlin 编译、Debug APK 构建和 `git diff --check`。
- 最新 Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，`214,432,460` bytes，SHA-256 `41A9157489B9F214D822C386E47F53B7434CA64F44C3A413743B08B1DE3D9184`。
- 设备当前仍处于锁屏状态，安装最新包仍被系统返回 `INSTALL_FAILED_ABORTED: User rejected permissions`，因此尚未完成最新包的真机启动确认；不创建新 Release，工作区继续保留用户未跟踪目录 `tmp/`。

## 2026-08-29 17:02

- 设备已成功安装并启动上一版 Debug APK，确认 `ViewTreeLifecycleOwner` 问题已消失；新日志进一步暴露 ComposeView 要求 `ViewTreeSavedStateRegistryOwner`，因此新增与 FlutterActivity 生命周期同步的轻量 SavedStateOwner，并将其安装到 FlutterView、Activity 根视图和 ComposeView。
- 原生视图树兼容代码改为 Java 辅助层，显式覆盖 FlutterView 根节点；新增 `androidx.savedstate:savedstate-android:1.4.0` 依赖。Android 原生单测、Kotlin 编译和 Debug APK 构建均通过。
- 最新 Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，`214,432,460` bytes，SHA-256 `032F54C849001705F1590DB5E25C7FD9DF4F06160CCAF8D1344F8C0823BE3B7E`。
- 当前设备上的 16:53 包仍是上一构建，最新 17:02 包尚未完成设备安装确认；不创建新 Release，工作区继续保留用户未跟踪目录 `tmp/`。

## 2026-08-29 17:04

- 增加液态玻璃平台视图挂载后的二次 ViewTree owner 绑定：覆盖创建时 FlutterView 尚未进入 Activity 视图树的时序，避免首次 measure 时再次缺少 Lifecycle/SavedState owner。
- 验证通过：Android `:app:testDebugUnitTest`、Kotlin 编译、Debug APK 构建和 `git diff --check`；最新 Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，`214,432,460` bytes，SHA-256 `276BEEE7CFAAC3DD7DB7EFB0B3DFB44024C9EF36C43001041CB24B8DF1EF9D75`。
- 设备端覆盖安装仍返回 `INSTALL_FAILED_ABORTED: User rejected permissions`，最新包尚未完成真机启动确认；不创建新 Release，工作区继续保留用户未跟踪目录 `tmp/`。

## 2026-08-29 17:28

- 对照 BiliPai 与 Kyant 官方示例修复液态玻璃视觉退化：原生表面从 `drawPlainBackdrop` 恢复为带 `Highlight`、`Shadow`、`InnerShadow` 的 `drawBackdrop`，底栏选中胶囊增加独立 lens、深度折射和色散层，按压缩放调整为轻量弹性。
- 扩大 Flutter 背板局部取样窗口并保留真实坐标，避免把目标矩形截图拉伸后丢失周围像素；通过显式 padding 让 Kyant lens 能访问折射边缘的取样内容。继续使用 TLHC/Virtual Display、SurfaceView PixelCopy、30 FPS 限流和现有异常熔断策略。
- 新增取样窗口边界与目标 inset 单测；Android `:app:testDebugUnitTest`、Kotlin 编译、Debug `assembleDebug`、目标 Dart analyze 均通过。
- 新 Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，SHA-256 `DB484BEC24F9CC0D7637541671E6374ADBF406D768C37C36DE9D4C14DC4470DC`；设备仍处于锁屏/通知遮罩，覆盖安装返回 `INSTALL_FAILED_ABORTED: User rejected permissions`，因此未完成真机视觉回归。
- 当前版本仍为 `v26.8.29.3` / `26.8.29+3`，不创建新 Release；工作区继续保留用户未跟踪目录 `tmp/`，源码和记录尚未提交。

## 2026-08-29 17:37

- 按用户要求撤回 Android Kyant 液态玻璃方案：移除 Compose/Kyant 依赖、原生 PlatformView/取样实现、Flutter 包装层、设置开关、许可证和对应 Dart/Android 单测。
- 已恢复浮动/固定底栏、首页搜索胶囊和普通页面悬浮按钮的原有 Flutter/磨砂渲染；播放器、HDR SurfaceView、播放器洞察及此前其它修复保持不变。
- 保留 `BiliDocumentsProvider` 的 `${applicationId}.MTDataFilesProvider` 修复，以避免 Debug/Release Provider 冲突；保留用户未跟踪目录 `tmp/`，未执行整仓回退。
- 验证：Flutter `test --no-pub` 11/11 通过；Flutter 全量 analyze 无 error（仅项目既有 info）；Android `:app:compileDebugKotlin` 从 `android` 目录通过；`git diff --check` 通过。
- 当前版本仍为 `v26.8.29.3` / `26.8.29+3`，不创建新 Release；回退后的源码和记录尚未提交。

## 2026-08-29 18:11

- 修复播放器洞察摘要点击区域过小的问题：摘要点击层改为不透明命中，黑色 surface 的留白区域也可进入详情；智能摘要开始渐隐后的 350ms 内继续保留点击能力。
- 新增播放器洞察交互回归测试，覆盖摘要留白点击和智能摘要渐隐期间点击展开详情；保留此前 Provider authority 修复。
- 按同日版本规则将正式版本准备为 `v26.8.29.4` / `26.8.29+4`，发布说明已写入 `version/release-notes-v26.8.29.4.md`；等待正式双 ABI 构建和发布。
- 验证：Flutter 工具链 3.47.2、`flutter pub get`、全量 `flutter test --no-pub` 12/12、全量 analyze 无 error（仅项目既有 info）、`git diff --check` 通过。

## 2026-08-29 18:19

- 已发布正式版 `v26.8.29.4`，发布提交为 `ae6c0fcc286a2a99cd97b403a5b0a1dedea555ff`，已推送至 `maxzrb/PiliExo` 的 `main` 并创建带注释标签。
- GitHub Release：<https://github.com/maxzrb/PiliExo/releases/tag/v26.8.29.4>；两个 ABI 资产状态均为 `uploaded`。
- ModelScope：<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.4/PiliExo_android_v26.8.29.4_arm64-v8a.apk>、<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.4/PiliExo_android_v26.8.29.4_armeabi-v7a.apk>；均返回 HTTP 200，长度和 `X-Linked-ETag` 与本地产物一致。
- arm64 APK：`31,662,286` bytes，SHA-256 `2F93405EC16B18C054DD65899754FDD193AAF7F995EFF610EF1CF334407A5110`；armeabi-v7a APK：`31,536,417` bytes，SHA-256 `39CC232BE1BE933A2EC64586E4BF8E37325E8F58FF7B6D71F737B5328691F616`。
- 发布验证：Flutter 3.47.2 工具链校验、`flutter pub get`、`flutter test --no-pub` 12/12、全量 analyze 无 error、双 ABI `aapt2` 包名/版本/ABI/FFmpeg 资源核验、既有正式证书 V2 签名核验、`git diff --check` 全部通过。
- 当前版本为 `v26.8.29.4` / `26.8.29+4`；正式构建使用既有 `CN=PiliExo, O=AerithDream, C=CN` 4096 位 RSA 签名，工作区仅保留用户未跟踪目录 `tmp/`，不纳入版本控制。

## 2026-08-29 18:46

- 改进自动/手动更新下载交互：发现新版本后沿用同一个更新弹窗，点击下载后弹窗切换为下载状态，显示当前阶段、进度条和已下载/总大小，不再关闭弹窗后仅显示无交互的加载提示。
- Android Aria2-next 下载通过更新 MethodChannel 按约 250ms 回传文件大小；非 ARM64 的 Dio HTTP 回退使用 `onReceiveProgress`，两条路径都支持已知 Release 资产大小和未知大小的不确定进度。
- 增加弹窗内“取消下载”操作，取消会终止 Aria2 进程或 Dio 请求，不回退到浏览器，也不会安装未完成文件；关闭更新弹窗时同样取消正在进行的下载。
- 修改文件：`lib/utils/update.dart`、`android/app/src/main/kotlin/com/example/piliplus/AndroidUpdatePlugin.kt`、`test/utils/update_asset_test.dart`。
- 验证通过：Flutter `test --no-pub` 14/14；全量 `flutter analyze --no-pub --no-fatal-infos` 无 error（保留项目既有 42 条 info）；Android `:app:assembleDebug --console=plain --warning-mode=none` 成功；`git diff --check` 通过。
- 当前版本仍为 `v26.8.29.4` / `26.8.29+4`，本轮不递增版本号、不创建新 Release；工作区保留用户未跟踪目录 `tmp/`，三处源码/测试文件及本记录尚未提交。

## 2026-08-29 19:00

- 按用户要求不递增版本，已将更新下载弹窗交互修复覆盖到正式版 `v26.8.29.4`；源码提交为 `7a2edd7c9fd1ee9aaaf71e5052301ed04b60c5e2`，同名标签已强制移动到该提交。
- GitHub Release 已原地替换同名双 ABI 资产并更新说明：<https://github.com/maxzrb/PiliExo/releases/tag/v26.8.29.4>。
- ModelScope 同路径资产已覆盖：<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.4/PiliExo_android_v26.8.29.4_arm64-v8a.apk>、<https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/releases/v26.8.29.4/PiliExo_android_v26.8.29.4_armeabi-v7a.apk>。
- 新 arm64 APK：`31,666,544` bytes，SHA-256 `0828E730F59173416761ECE5467907F625BD1B51487F502D7F7277BF6C1CA359`；新 armeabi-v7a APK：`31,542,223` bytes，SHA-256 `A54C25EE33934229554ADB1B012748AFF9E44CA05425D729A4243D09F4892197`。GitHub digest 与 ModelScope `X-Linked-ETag` 均已回读一致。
- 发布包核验通过：包名 `com.maxzrb.piliexo`、`versionName=26.8.29`、`versionCode=4`、双 ABI、正式证书 `CN=PiliExo, O=AerithDream, C=CN` 4096 位 RSA、V2 签名；Flutter 测试 14/14、Android Release 构建均通过。
- 当前工作区已推送 `origin/main`，仅保留用户未跟踪目录 `tmp/`；发布记录已提交，不修改用户未跟踪目录 `tmp/`。
