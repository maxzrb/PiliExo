/// 解析视频链接的毫秒起点，弹幕跳转提前三秒并钳制到零。
int? parseVideoLinkProgress(Map<String, String> queryParameters) {
  if (queryParameters['start_progress'] case final progress?) {
    return int.tryParse(progress);
  }
  if (queryParameters['dm_progress'] case final progress?) {
    final value = int.tryParse(progress);
    return value == null ? null : (value > 3000 ? value - 3000 : 0);
  }
  final seconds = double.tryParse(queryParameters['t'] ?? '');
  return seconds != null && seconds.isFinite ? (seconds * 1000).toInt() : null;
}
