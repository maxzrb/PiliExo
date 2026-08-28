# PiliExo AI 工作状态

- 更新时间：2026-08-28 23:07 (+08:00)
- 工作分支：`feature/android-media3-hdr`
- 分析基线：`ea67b9313f5513bd0752f9d144e78036c40e5104`
- 发布提交：`1669ff368df0c12a72e92fe409c3b84737c925d5`
- 目标：PiliExo 仅 Android 在线 UGC/PGC HDR 使用 Media3 原生 SurfaceView；SDR、直播和离线保持 mpv；应用包名独立为 `com.maxzrb.piliexo`，外观磨砂效果可配置。

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

## 验证

- `flutter test --no-pub`：通过，8 个测试全部通过，其中包含 Android ABI 资产选择测试；本机 SDK 为 3.47.1，而同步后的 `pubspec.yaml` 要求 3.47.2，普通 `flutter test` 因版本解析被阻止。
- Media3 1.11.0 + OkHttp 5.3.0 独立 Android API 工程：Kotlin 编译及 `HdrMedia3SourceTest` 通过（含 5xx、Range 和断流续传）。
- 目标文件定向 `flutter analyze`：无 error，仅有 lint info。
- `git diff --check`：通过；仅报告仓库既有的 LF/CRLF 自动转换提示。
- 使用项目补丁脚本修复 Flutter 3.47.1 与项目 `material_ui` 的基线兼容后，Android `assembleDebug` 构建通过。
- APK 已生成：`build/app/outputs/flutter-apk/app-debug.apk`，201236035 bytes；最新 SHA-256 为 `ABCC62569508456C5B7872AB725F611BBF227B88B5AE5FDE95E9E3A9A44BCBDC`。
- 全量 `flutter test`：通过。
- Android `assembleRelease`：通过（缓存 Gradle、Media3 1.11.0、OkHttp 5.3.0）。
- Android `:app:testDebugUnitTest -Pkotlin.incremental=false`：通过（本轮加入 FFmpeg 音频扩展后复验）。
- Android Gradle 9.5 `:app:assembleRelease -Pkotlin.incremental=false -Psplit-per-abi=true -Ptarget-platform=android-arm,android-arm64`：通过；生成 arm64/v7a 测试包，均为 `versionCode=2`，并核验 `libffmpegJNI.so` 与对应 native ABI。
- AAR 与 release APK 核验通过：保留 `FfmpegAudioRenderer`，APK 不含 x86/x86_64；E-AC-3-JOC 软件路径以 PCM 出声为目标，不保证 Atmos 对象直通。
- Release APK：`dist/PiliExo_android_v26.8.28.1.apk`，68,793,128 bytes；SHA-256 为 `9D64CAD5C991485E4DCB323C2DAA8FA2DC5F8B300C97EA7DD8C71190B2D5664F`；包名保持 `com.example.piliplus`，显示名为 `PiliExo`。
- v26.8.28.2 arm64 Release APK：`dist/PiliExo_android_v26.8.28.2_arm64-v8a.apk`，26,601,707 bytes；SHA-256 为 `94EA78F3AA2458B9C56F264ED8A99BAF8971AD0390B010FABFD7C558C6B371A6`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- v26.8.28.2 v7a Release APK：`dist/PiliExo_android_v26.8.28.2_armeabi-v7a.apk`，26,480,705 bytes；SHA-256 为 `E9234886FC779CBC424A8B6965AB256353753549FFE973EDEBAA8C18EE4B196C`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- v26.8.28.2 Release 仅包含 `arm64-v8a`、`armeabi-v7a` 两种 native ABI；相较 v26.8.28.1 通用包，单包体积降低约 61%。
- v26.8.28.3 arm64 Release APK：`dist/PiliExo_android_v26.8.28.3_arm64-v8a.apk`，26,603,903 bytes；SHA-256 为 `2B13DAA38924C02708549A61F09AFF7AA2844425AD8BC79C994D6E9DE390E686`；包名为 `com.maxzrb.piliexo`，versionCode 为 3。
- v26.8.28.3 v7a Release APK：`dist/PiliExo_android_v26.8.28.3_armeabi-v7a.apk`，26,479,041 bytes；SHA-256 为 `45C3AC59CB541BE496CC85715A5D8342744308A667019F2EBD3F941D92E7E283`；包名为 `com.maxzrb.piliexo`，versionCode 为 3。
- v26.8.28.2 arm64 正式 Release APK：`dist/PiliExo_android_v26.8.28.2_arm64-v8a.apk`，26,603,631 bytes；SHA-256 为 `05E64EB063878F55DEE512B533BEB2BE1CCC6A39DC9CBB35A163DCA7A1FA027E`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- v26.8.28.2 v7a 正式 Release APK：`dist/PiliExo_android_v26.8.28.2_armeabi-v7a.apk`，26,479,433 bytes；SHA-256 为 `05674F4765F134944B4E1B1DA3B63B192C2D85C025808D1BCBAFBC9E499EB0D1`；包名为 `com.maxzrb.piliexo`，versionCode 为 2。
- GitHub `v26.8.28.2` Release 资产状态为 `uploaded`；ModelScope `resolve/master/releases/v26.8.28.2/...apk` 两个地址实测 HTTP 200。

## 当前限制

- 完整 `flutter analyze --no-pub` 报告 42 条 info/lint，无 error；包含项目既有弃用提示和新增 HDR 文件的风格提示。
- Release APK 使用本机已打补丁的 Flutter 3.47.1 构建；源码依赖声明已随上游同步为 Flutter 3.47.2，后续 CI 将按声明版本构建。
- 设备端安装权限确认仍由用户自行处理；代理未再次安装或启动 APK。
- 当前环境没有本轮 HDR/振动真机验收，SurfaceFlinger dataspace、HDR 屏幕模式、首帧、震动振幅、磨砂效果和长时间音画同步仍需实测。
- 本地未提供 `android/key.properties`，本次自用 Release APK 使用 Gradle debug keystore 兜底签名；正式公开分发前仍应配置固定的正式签名。
- 正式版本已按远端最新 Release 的 N+1 规则固定为 `26.8.28+2`；此前 `v26.8.28.3` 仅为历史测试构建，远端没有对应正式标签或 Release；后续测试包继续沿用 `+2`，下一次正式发布再读取远端最新标签递增。

## 下一步

- 用户自行按设备 ABI 安装 `v26.8.28.2` APK 后，验收默认震动、滑块即时反馈、磨砂开关与三档效果、HDR10、Dolby Vision、HDR Vivid、横竖屏、前后台、画中画、拖动、字幕和 30 分钟连续播放。
- 复测 SDR↔HDR 切换红屏和返回播放列表残帧；确认无残留后再按 Release 标签继续迭代。
- 后续再规划手机顶部状态栏跟随视频模糊/变色和播放洞察；本轮不实现、不打新 Release。

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
