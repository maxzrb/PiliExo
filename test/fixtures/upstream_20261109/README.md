# 2026-11-09 上游适配固定样例

`input.json` 保存旧版下载元数据、离线字幕/看点和线程式评论树；`reference.json` 是按旧缓存兼容规则与评论树前序规则独立确定的参考输出。

测试只读取这两份文件，不自动更新参考值，不创建测试 App。覆盖：

- 旧版秒级 `time_update_stamp` / `time_create_stamp` 读取时迁移为毫秒，写回保持毫秒。
- 离线字幕按中文优先、AI 最后排序，并从条目目录解析本地路径。
- 离线看点按视频总时长归一化进度。
- 评论树按 ctime 前序展开，并验证指定深度自动折叠。

执行：`flutter test --no-pub test/utils/upstream_20261109_test.dart`
