# 楼中楼加载进度固定样例

采用 `input.json` 和 `reference.json` 对照，直接调用生产代码中的纯函数
`lib/utils/reply_progress.dart`。测试不请求平台、不依赖真实回复数据。

覆盖：

- 首屏、后续页、重复 id 超出总数、未知总数、总数被覆盖为 0、服务端结束；
- 刷新采用新总数、刷新归零、后续页 0 不覆盖、后续页更大/更小；
- 重复回复 id 只计一次。

运行：

```powershell
& 'C:/Users/maxzr/.codex/vendor_imports/flutter-3.47.9/bin/flutter.bat' test --no-pub --reporter expanded test/utils/reply_progress_test.dart
```
