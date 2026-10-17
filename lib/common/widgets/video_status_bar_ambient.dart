import 'dart:ui' as ui;

import 'package:PiliPlus/plugin/pl_player/models/ambient_frame.dart';
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
    this.texture,
    this.blurSigma = 24.0,
  });

  final ValueListenable<ui.Image?>? frame;
  final double blurSigma;
  final ValueListenable<AmbientTextureFrame?>? texture;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    if (frame == null) return const SizedBox.expand();

    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([frame, texture]),
        builder: (context, child) {
          final image = frame.value;
          final video = texture?.value;
          if (image == null && video == null) return const SizedBox.expand();
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: video != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          child: SizedBox.fromSize(
                            size: video.viewportSize,
                            child: ColoredBox(
                              color: video.fill,
                              child: ClipRect(
                                child: Transform.flip(
                                  flipX: video.flipX,
                                  flipY: video.flipY,
                                  child: FittedBox(
                                    fit: video.fit,
                                    alignment: video.alignment,
                                    child: SizedBox.fromSize(
                                      size: video.videoSize,
                                      child: Texture(
                                        textureId: video.textureId,
                                        filterQuality: FilterQuality.low,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : RawImage(
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
