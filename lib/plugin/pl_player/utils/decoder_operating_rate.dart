import 'dart:math' as math;

/// 在打开视频时按已知源帧率和用户的倍速需求规划解码吞吐，不限制呈现帧率。
abstract final class DecoderOperatingRate {
  static double? parseFrameRate(String? value) {
    if (value == null) return null;
    final parts = value.trim().split('/');
    if (parts.length > 2) return null;
    final numerator = double.tryParse(parts.first);
    final denominator = parts.length == 1 ? 1.0 : double.tryParse(parts.last);
    if (numerator == null || denominator == null || denominator <= 0) {
      return null;
    }
    final fps = numerator / denominator;
    // 缺失、异常或不可信的元数据交回原解码策略，不猜测一个固定高值。
    return fps.isFinite && fps > 0 && fps <= 240 ? fps : null;
  }

  static int? plan({
    required bool isAndroid,
    required bool hardwareEnabled,
    required bool isLive,
    required bool audioOnly,
    required String? frameRate,
    required double baseRate,
    required double temporaryRate,
  }) {
    if (!isAndroid || !hardwareEnabled || isLive || audioOnly) return null;
    final fps = parseFrameRate(frameRate);
    if (fps == null ||
        !baseRate.isFinite ||
        !temporaryRate.isFinite ||
        baseRate <= 0 ||
        temporaryRate <= 0) {
      return null;
    }
    final demand = fps * math.max(baseRate, temporaryRate);
    return demand.isFinite && demand <= 0x7fffffff ? demand.ceil() : null;
  }
}
