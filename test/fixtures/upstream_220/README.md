# 2.2.0 回归样例

采用 FATE 的固定样例输入与参考输出思路，由项目现有 Flutter 测试运行器执行，不创建测试 App，也不声称调用 FFmpeg 的原生 FATE 框架。

- input.json：固定订阅接口响应、滚动参数与标准 ZIP 的 Base64 样例。
- reference.json：人工按预期行为确定的输出，测试时只读取，不根据实际结果自动更新。
- ZIP 样例使用固定时间和无压缩条目；CRC 样例只改变中央目录校验值，截断样例只保留前半段。正常样例用于验证旧标准 ZIP 的兼容性。
- 执行：flutter test --no-pub test/utils/scroll_offset_helper_test.dart test/pages/subscription_order_test.dart test/utils/upstream_integration_test.dart
