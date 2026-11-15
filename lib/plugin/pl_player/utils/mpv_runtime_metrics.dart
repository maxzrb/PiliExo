/// 保存 mpv 已报告的属性；未报告的计数不能当作零掉帧。
class MpvRuntimeMetrics {
  int? outputDroppedFrames;
  int? decoderDroppedFrames;
  int? forwardBytes;
  double? cacheDuration;
  int recentDroppedFrames = 0;
  int? _previousOutputDroppedFrames;
  int? _previousDecoderDroppedFrames;
  int _totalDroppedFrames = 0;

  bool get droppedFramesAvailable =>
      outputDroppedFrames != null || decoderDroppedFrames != null;

  int get droppedFrames => _totalDroppedFrames;

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

  /// 输出和解码计数独立累计，单项清零或暂时未知不能清掉历史或相互抵扣。
  void finishSample() {
    recentDroppedFrames =
        _delta(outputDroppedFrames, _previousOutputDroppedFrames) +
        _delta(decoderDroppedFrames, _previousDecoderDroppedFrames);
    _totalDroppedFrames += recentDroppedFrames;
    if (outputDroppedFrames != null && outputDroppedFrames! >= 0) {
      _previousOutputDroppedFrames = outputDroppedFrames;
    }
    if (decoderDroppedFrames != null && decoderDroppedFrames! >= 0) {
      _previousDecoderDroppedFrames = decoderDroppedFrames;
    }
  }

  static int _delta(int? current, int? previous) {
    if (current == null || current < 0) return 0;
    if (previous == null || current < previous) return current;
    return current - previous;
  }
}
