import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 将视频当前帧渲染为手机顶部系统状态栏的环境背景。
///
/// 这不是播放器或视频卡片的转场模糊：组件只占用页面最顶部的状态栏 inset，
/// 播放器本身保持原有的 SurfaceView、纹理和交互链路。
class VideoStatusBarAmbient extends StatelessWidget {
  const VideoStatusBarAmbient({
    super.key,
    required this.frame,
    this.blurSigma = 24.0,
  });

  final ValueListenable<ui.Image?>? frame;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    if (frame == null) return const SizedBox.expand();

    return IgnorePointer(
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: frame,
        builder: (context, image, child) {
          if (image == null) return const SizedBox.expand();
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: RawImage(
                    image: image,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.low,
                  ),
                ),
                const ColoredBox(color: Color(0x57000000)),
              ],
            ),
          );
        },
      ),
    );
  }
}
