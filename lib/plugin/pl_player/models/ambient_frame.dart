import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 对照开关只改变取图实现，不改变采样间隔、模糊强度或持久偏好。
abstract final class AmbientFramePolicy {
  static const compare = bool.fromEnvironment('PILI_POWER_COMPARE_AMBIENT');
  // 总CPU虽略降，但栅格线程开销上升，真实功耗未确认前只用于研究。
  static const gpuTexture = bool.fromEnvironment('PILI_AMBIENT_GPU_TEXTURE');
  // RGBA尚未证明整体收益，日常保留PNG；对照研究可在同一包内切换。
  static const rawPixels = bool.fromEnvironment('PILI_AMBIENT_RAW_RGBA');
  static final optimized = ValueNotifier(true);
}

/// 复用现有视频纹理，只传递布局元数据，不创建第二个解码器。
@immutable
class AmbientTextureFrame {
  const AmbientTextureFrame({
    required this.textureId,
    required this.viewportSize,
    required this.videoSize,
    required this.fit,
    required this.alignment,
    required this.fill,
    required this.flipX,
    required this.flipY,
  });

  final int textureId;
  final Size viewportSize;
  final Size videoSize;
  final BoxFit fit;
  final Alignment alignment;
  final Color fill;
  final bool flipX;
  final bool flipY;

  @override
  bool operator ==(Object other) =>
      other is AmbientTextureFrame &&
      textureId == other.textureId &&
      viewportSize == other.viewportSize &&
      videoSize == other.videoSize &&
      fit == other.fit &&
      alignment == other.alignment &&
      fill == other.fill &&
      flipX == other.flipX &&
      flipY == other.flipY;

  @override
  int get hashCode => Object.hash(
    textureId,
    viewportSize,
    videoSize,
    fit,
    alignment,
    fill,
    flipX,
    flipY,
  );
}

/// 原生明确提供RGBA顺序和行跨度，避免依赖Bitmap内存字节序。
class AmbientRgbaFrame {
  AmbientRgbaFrame._(this.pixels, this.width, this.height, this.rowBytes);

  final Uint8List pixels;
  final int width;
  final int height;
  final int rowBytes;

  static AmbientRgbaFrame? fromMessage(Object? message) {
    if (message is! Map || message['format'] != 'rgba8888') return null;
    final width = message['width'];
    final height = message['height'];
    final rowBytes = message['rowBytes'];
    final pixels = message['pixels'];
    if (width is! int ||
        height is! int ||
        rowBytes is! int ||
        pixels is! Uint8List ||
        width < 1 ||
        width > 256 ||
        height < 1 ||
        height > 256 ||
        rowBytes < width * 4 ||
        rowBytes > 256 * 4 ||
        pixels.length != rowBytes * height) {
      return null;
    }
    return AmbientRgbaFrame._(pixels, width, height, rowBytes);
  }

  Future<ui.Image> toImage() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        rowBytes: rowBytes,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
