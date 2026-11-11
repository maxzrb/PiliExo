# 项目约束

## 文件处理

- 所有文件读写使用 UTF-8 编码，修改时不得改变原有编码。
- PowerShell 读取中文文件前，执行 `chcp 65001` 并设置 UTF-8 输出，使用 `Get-Content -Encoding UTF8`。
- 不得使用 sed/awk 处理中文文件，改用 Python 或 Node.js。
- 新增代码注释使用中文。

## 构建与发布

- 不得使用 GitHub Actions 构建；所有构建、打包和签名均在本机完成。
- 不得触发或重新启用本仓库的 GitHub Actions。2026-10-18 已在仓库设置禁用 Actions。
- 发布使用原正式证书，不得提交签名密钥、密码或访问令牌。

## 发布防回归

- 不得只凭编译成功判断 APK 可用。发布前必须覆盖安装并冷启动到可用页面；如果用户在发布完成前明确要求跳过设备验收，记录不得写成已通过。
- 隔离构建目录也必须包含 `flutter pub get` 生成的 Android 插件注册文件。构建前运行 `lib/scripts/verify_android_plugins.ps1`；构建后运行 `tool/verify_release_apk.py` 检查 `classes.dex` 中的 `GeneratedPluginRegistrant`、AOT 源码提交和必要原生库。
- 同版本覆盖发布必须核对 AOT 内嵌源码提交与最终源码提交一致。标签不得移动；覆盖包及其源码修订提交、产物哈希和验证边界必须记录。
- 用户导出的设置只能用于公开偏好默认值。登录凭证、Cookie、用户或设备标识、WebDAV 地址与凭据、设备显示模式和屏幕派生值不得写入默认设置或提交到仓库。
- 启动页卡住时先区分进程存活、主线程或 Dart 初始化阻塞和系统 Splash 未移除。必须结合正常包对照、`classes.dex` 内容、插件注册日志与真机冷启动验证，不能只根据“没有崩溃”判断为网络问题。
