import 'package:flutter/widgets.dart';

/// 按播放路线选择折叠方式：mpv 兼容路线随页头缩小，原生 HDR 只裁剪。
class CollapsingVideoViewport extends StatelessWidget {
  const CollapsingVideoViewport({
    super.key,
    required this.animateShrink,
    required this.width,
    required this.height,
    required this.child,
  });

  final bool animateShrink;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (animateShrink) return child;
    return FixedVideoViewport(width: width, height: height, child: child);
  }
}

/// 滚动折叠时只裁剪可视区域，保持原生视频窗口尺寸，避免反复重建缩小的输出缓冲。
class FixedVideoViewport extends StatelessWidget {
  const FixedVideoViewport({
    super.key,
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: width,
      maxWidth: width,
      minHeight: height,
      maxHeight: height,
      child: child,
    ),
  );
}
