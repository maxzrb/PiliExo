# 2026-11-04 上游适配固定样例

input.json 保存固定接口响应、评论游标、签名输入、刷新状态和投屏 URL；reference.json 是按需求与协议确定的参考输出。测试只读取两份文件，不自动更新参考答案，不创建测试 App。
番剧/课程使用内存 HTTP 适配器；评论调用实际分页控制器；刷新使用现有 Flutter widget 测试；投屏验证固定版本依赖的 URL 解析。它们不替代真实账号权限、电视发现和手机解码验收。
签名使用公开测试 key/secret 和固定时间，没有真实凭据；参考摘要以明确的规范查询串独立计算。
执行：flutter test --no-pub test/http/video_url_test.dart test/utils/upstream_20261104_test.dart
