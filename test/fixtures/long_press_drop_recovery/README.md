# 长按松手恢复期丢帧统计固定样例

使用固定 sample input/reference output，复用现有 Flutter 测试运行器，不创建测试 App。
松手后由控制器开启 500 毫秒恢复期，边界先收取计数再结束排除；提前再次长按或手动切速时同样先结清窗口。
input.json 描述固定计数事件，reference.json 为手工确定的每步预期：[正常总丢帧, 近期丢帧, 后端原始总数, 排除总数]。
release/end 表示控制器的恢复期开始与边界采样后的结束；transition 是原有五帧切速额度，reset 是切源重置。
参考答案不从实际结果生成。覆盖大量恢复丢帧、历史保留、exact清零、窗口结束后立即计数、再次长按、切源、跨秒和普通切速不变。
执行：flutter test --no-pub test/plugin/pl_player/long_press_drop_recovery_test.dart
