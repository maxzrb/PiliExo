# 播放权限响应边界固定样例

采用 input.json 和 reference.json 对照，调用生产代码 VideoHttp.videoUrl，复用 test/http/video_url_test.dart 的内存 HTTP 适配器。测试不会请求平台、读取真实账号或播放媒体；fixture.invalid 仅为不可用的样例地址。

四个样例分别验证 UGC 拒绝、tryLook 参数下拒绝、拒绝响应附带媒体字段和 PGC 业务拒绝。参考输出核对错误状态、请求次数和无播放模型/媒体条目。

运行：

```powershell
& 'C:/Users/maxzr/.codex/vendor_imports/flutter-3.47.9/bin/flutter.bat' test --no-pub --reporter expanded test/http/video_url_test.dart
```

验证边界：这些是人工构造的拒绝响应，不是平台返回记录。通过仅证明当前源码对这四类输入的行为，不能证明平台实际鉴权正确、播放器已完整播放，也不能还原未知修改版的手法。未提供对方样本前，不据此认定发生破解或推荐修改生产鉴权逻辑。
