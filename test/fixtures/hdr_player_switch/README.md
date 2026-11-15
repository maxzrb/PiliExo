# HDR 播放器切换回归样例

使用固定输入与独立参考输出，由现有 Flutter 测试运行器执行，不创建测试 App。
input.json 定义实际页面控制器的起始播放状态和加载响应；reference.json 按需求人工确定调用参数与最终后端，不根据运行结果自动生成。
测试替换原生播放边界，调用产品 switchHdrPlayer，验证进度、暂停、重复点击、繁忙、回退与失败清理；原生解码和 Surface 交接仍需真实设备播放验收。
执行：flutter test --no-pub test/plugin/pl_player/hdr_player_switch_test.dart
