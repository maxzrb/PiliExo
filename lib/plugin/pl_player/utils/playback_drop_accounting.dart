import 'dart:math' as math;

/// 区分起播/切速重对齐、孤立丢弃与持续播放异常；原始计数始终保留。
/// 复用既有一秒采样，不增加定时器或原生查询；不根据计数断言设备故障。
class PlaybackDropAccounting {
  static const startupWindowMs = 3000;
  static const transitionWindowMs = 2000;
  static const maxContinuousTransitionMs = 6000;
  static const severeIntervalFrames = 12;

  int rawDroppedFrames = 0;
  int droppedFrames = 0;
  int recentDroppedFrames = 0;
  int get excludedDroppedFrames => rawDroppedFrames - droppedFrames;
  bool _startupPending = true;
  bool _settling = true;
  int? _windowUntilMs;
  int? _transitionBurstStartMs;
  int? _lastTransitionMs;
  int _intervalFrames = 0;
  int _pendingFrames = 0;
  bool _previousIntervalDropped = false;

  void reset() {
    rawDroppedFrames = droppedFrames = recentDroppedFrames = 0;
    _startupPending = _settling = true;
    _windowUntilMs = _transitionBurstStartMs = _lastTransitionMs = null;
    _resetEvidence();
  }

  void _resetEvidence() {
    _intervalFrames = _pendingFrames = 0;
    _previousIntervalDropped = false;
  }

  void firstFrame(int nowMs) {
    if (!_startupPending) return;
    _startupPending = false;
    _windowUntilMs = nowMs + startupWindowMs;
    _transitionBurstStartMs = nowMs;
    _settling = true;
    _resetEvidence();
  }

  void speedTransition(int nowMs) {
    final last = _lastTransitionMs;
    _lastTransitionMs = nowMs;
    if (last == null || nowMs - last > transitionWindowMs) {
      _transitionBurstStartMs = nowMs;
    }
    final start = _transitionBurstStartMs ??= nowMs;
    // 连续切速最多宽限六秒，不能反复长按而无限屏蔽真实性能不足。
    final next = math.min(
      nowMs + transitionWindowMs,
      start + maxContinuousTransitionMs,
    );
    if (next <= nowMs) return;
    _windowUntilMs = next;
    _settling = true;
    _resetEvidence();
  }

  void sample(
    int total, {
    required int nowMs,
    bool finishInterval = false,
    bool isPlaying = true,
    bool isBuffering = false,
  }) {
    total = math.max(0, total);
    if (total < rawDroppedFrames) {
      // 切源或后端计数重置时不继承旧计数和持续性证据。
      rawDroppedFrames = droppedFrames = recentDroppedFrames = 0;
      _resetEvidence();
    }
    final delta = total - rawDroppedFrames;
    rawDroppedFrames = total;
    if (!isPlaying || isBuffering) {
      // 暂停和网络缓冲不归因为设备性能，恢复时重新收集稳定区间。
      _resetEvidence();
      _settling = true;
      recentDroppedFrames = 0;
      return;
    }
    final inWindow =
        _startupPending || (_windowUntilMs != null && nowMs <= _windowUntilMs!);
    if (inWindow || _settling) {
      // 丢弃跨越窗口边界的一次采样，避免延迟上报的过渡计数漏进稳定区间。
      _resetEvidence();
      recentDroppedFrames = 0;
      if (finishInterval && !inWindow) _settling = false;
      return;
    }
    _intervalFrames += delta;
    if (!finishInterval) return;
    final frames = _intervalFrames;
    _intervalFrames = 0;
    recentDroppedFrames = 0;
    if (frames == 0) {
      _pendingFrames = 0;
      _previousIntervalDropped = false;
      return;
    }
    // 连续两个采样区间都有丢帧才确认为持续异常；严重突发直接报告。
    if (_previousIntervalDropped || frames >= severeIntervalFrames) {
      recentDroppedFrames = _pendingFrames + frames;
      droppedFrames += recentDroppedFrames;
      _pendingFrames = 0;
    } else {
      _pendingFrames = frames;
    }
    _previousIntervalDropped = true;
  }
}
