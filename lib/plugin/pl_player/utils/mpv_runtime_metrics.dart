/// 保存 mpv 已报告的属性；未报告的计数不能当作零掉帧。
class MpvRuntimeMetrics {
  int? outputDroppedFrames;

  /// 仅保留 mpv 的估算值供排查，不进入播放器洞察。
  /// 该值会混入硬件解码队列延迟和主动跳帧，不能证明真实丢帧。
  int? decoderDroppedFrames;
  int? forwardBytes;
  double? cacheDuration;
  double? videoFrameRate;
  String? videoCodec;
  String? audioCodec;
  String? videoDecoder;
  String? audioDecoder;
  int recentDroppedFrames = 0;
  int? _previousOutputDroppedFrames;
  int _totalDroppedFrames = 0;

  bool get droppedFramesAvailable => outputDroppedFrames != null;

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

  /// 只累计实际未呈现的 VO 丢帧。
  ///
  /// decoder-frame-drop-count 是“可能丢弃”的启发式估算，正常硬件解码排队
  /// 和播放器主动跳过非参考帧都可能触发，不能计入恶性丢帧。
  void finishSample() {
    recentDroppedFrames = _delta(
      outputDroppedFrames,
      _previousOutputDroppedFrames,
    );
    _totalDroppedFrames += recentDroppedFrames;
    if (outputDroppedFrames != null && outputDroppedFrames! >= 0) {
      _previousOutputDroppedFrames = outputDroppedFrames;
    }
  }

  static int _delta(int? current, int? previous) {
    if (current == null || current < 0) return 0;
    if (previous == null || current < previous) return current;
    return current - previous;
  }
}
