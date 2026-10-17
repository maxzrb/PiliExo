/// 保存 mpv 已报告的属性；未报告的计数不能当作零掉帧。
class MpvRuntimeMetrics {
  int? outputDroppedFrames;
  int? decoderDroppedFrames;
  int? forwardBytes;
  double? cacheDuration;
  int recentDroppedFrames = 0;
  int? _previousDroppedFrames;

  bool get droppedFramesAvailable =>
      outputDroppedFrames != null || decoderDroppedFrames != null;

  int get droppedFrames =>
      (outputDroppedFrames ?? 0) + (decoderDroppedFrames ?? 0);

  double? get mediaBitsPerSecond {
    final bytes = forwardBytes;
    final duration = cacheDuration;
    if (bytes == null ||
        bytes <= 0 ||
        duration == null ||
        !duration.isFinite ||
        duration <= 0) {
      return null;
    }
    final value = bytes * 8 / duration;
    return value.isFinite && value > 0 ? value : null;
  }

  /// 每次采样完成后计算增量；切源或 seek 导致计数回退时重新建立基线。
  void finishSample() {
    final current = droppedFramesAvailable ? droppedFrames : null;
    final previous = _previousDroppedFrames;
    recentDroppedFrames =
        current != null && previous != null && current >= previous
        ? current - previous
        : 0;
    _previousDroppedFrames = current;
  }
}
