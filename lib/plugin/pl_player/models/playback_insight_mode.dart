import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 播放器洞察摘要在视频画面上的显示方式。
enum PlaybackInsightMode implements EnumWithLabel {
  always('显示'),
  smart('智能'),
  off('不显示'),
  ;

  @override
  final String label;

  const PlaybackInsightMode(this.label);
}
