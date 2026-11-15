import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 原生视频上方的字幕层，直接订阅播放实例，不依赖 Flutter 视频纹理。
class MpvHdrSubtitle extends StatefulWidget {
  const MpvHdrSubtitle({
    super.key,
    required this.subtitleStream,
    required this.initialSubtitle,
    required this.configuration,
    required this.enableDrag,
    required this.onUpdatePadding,
  });

  final Stream<Subtitle> subtitleStream;
  final Subtitle initialSubtitle;
  final SubtitleViewConfiguration configuration;
  final bool enableDrag;
  final ValueChanged<EdgeInsets> onUpdatePadding;

  @override
  State<MpvHdrSubtitle> createState() => _MpvHdrSubtitleState();
}

class _MpvHdrSubtitleState extends State<MpvHdrSubtitle> {
  late EdgeInsets _padding = widget.configuration.padding;

  @override
  void didUpdateWidget(covariant MpvHdrSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _padding = widget.configuration.padding;
  }

  @override
  Widget build(BuildContext context) {
    final configuration = widget.configuration;
    if (!configuration.visible) return const SizedBox.shrink();
    return StreamBuilder<Subtitle>(
      stream: widget.subtitleStream,
      initialData: widget.initialSubtitle,
      builder: (context, snapshot) {
        final content = snapshot.data?.toString() ?? '';
        if (content.trim().isEmpty) return const SizedBox.shrink();
        Widget text(TextStyle style) => Text(
          content,
          style: style,
          textAlign: configuration.textAlign,
          textScaler: TextScaler.noScaling,
        );
        Widget caption = configuration.strokeStyle == null
            ? text(configuration.style)
            : Stack(
                children: [
                  text(configuration.strokeStyle!),
                  text(configuration.style),
                ],
              );
        if (widget.enableDrag) {
          caption = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) => setState(() {
              _padding = _padding.copyWith(
                bottom: clampDouble(_padding.bottom - details.delta.dy, 0, 200),
              );
            }),
            onVerticalDragEnd: (_) => widget.onUpdatePadding(_padding),
            child: caption,
          );
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: _padding,
          alignment: Alignment.bottomCenter,
          child: caption,
        );
      },
    );
  }
}
