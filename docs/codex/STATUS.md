# PiliExo AI 工作状态

- 更新时间：2026-08-28 18:18 (+08:00)
- 工作分支：`feature/android-media3-hdr`
- 分析基线：`ea67b9313f5513bd0752f9d144e78036c40e5104`
- 发布提交：`f50faf24a631af5873825c8b72a4bdd6e05a5a1a`
- 目标：PiliExo 仅 Android 在线 UGC/PGC HDR 使用 Media3 原生 SurfaceView；SDR、直播和离线保持 mpv。

## 已完成

- 添加 Media3 1.11.0、OkHttp 5.3.0 依赖及原生 `SurfaceView` 布局。
- 注册 `piliplus/media3_hdr_surface` Hybrid Composition PlatformView、MethodChannel 和 EventChannel。
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
- 已创建 `maxzrb/PiliExo` fork、`AerithDream/PiliExo` 数据集并发布 `v26.8.28.1`。

## 验证

- `flutter test --no-pub`：通过，5 个测试全部通过；本机 SDK 为 3.47.1，而同步后的 `pubspec.yaml` 要求 3.47.2，普通 `flutter test` 因版本解析被阻止。
- Media3 1.11.0 + OkHttp 5.3.0 独立 Android API 工程：Kotlin 编译及 `HdrMedia3SourceTest` 通过（含 5xx、Range 和断流续传）。
- 目标文件定向 `flutter analyze`：无 error，仅有 lint info。
- `git diff --check`：通过；仅报告仓库既有的 LF/CRLF 自动转换提示。
- 使用项目补丁脚本修复 Flutter 3.47.1 与项目 `material_ui` 的基线兼容后，Android `assembleDebug` 构建通过。
- APK 已生成：`build/app/outputs/flutter-apk/app-debug.apk`，201236035 bytes；最新 SHA-256 为 `ABCC62569508456C5B7872AB725F611BBF227B88B5AE5FDE95E9E3A9A44BCBDC`。
- 全量 `flutter test`：通过。
- Android `:app:testDebugUnitTest -Pkotlin.incremental=false`：通过。
- Android `assembleRelease`：通过（缓存 Gradle、Media3 1.11.0、OkHttp 5.3.0）。
- Release APK：`dist/PiliExo_android_v26.8.28.1.apk`，68,793,128 bytes；SHA-256 为 `9D64CAD5C991485E4DCB323C2DAA8FA2DC5F8B300C97EA7DD8C71190B2D5664F`；包名保持 `com.example.piliplus`，显示名为 `PiliExo`。
- GitHub Release 资产状态为 `uploaded`；ModelScope `resolve/master/releases/v26.8.28.1/...apk` 实测 302 后返回 200。

## 当前限制

- 完整 `flutter analyze --no-pub` 报告 42 条 info/lint，无 error；包含项目既有弃用提示和新增 HDR 文件的风格提示。
- Release APK 使用本机已打补丁的 Flutter 3.47.1 构建；源码依赖声明已随上游同步为 Flutter 3.47.2，后续 CI 将按声明版本构建。
- 设备端安装权限确认仍由用户自行处理；代理未再次安装或启动 APK。
- 当前环境没有 HDR/振动真机验收，SurfaceFlinger dataspace、HDR 屏幕模式、首帧、震动振幅和长时间音画同步仍需实测。

## 下一步

- 用户自行安装 `v26.8.28.1` APK 后，验收所有底栏/侧栏导航震动强度、HDR10、Dolby Vision、HDR Vivid、横竖屏、前后台、画中画、拖动、字幕和 30 分钟连续播放。
- 复测 SDR↔HDR 切换红屏和返回播放列表残帧；确认无残留后再按 Release 标签继续迭代。

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
