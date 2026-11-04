import 'dart:math' as math;

/// 起播和普通切速最多排除五帧，长按松手恢复期单独排除。
/// 保留后端原始计数，不根据后端计数断言设备故障。
class PlaybackDropAccounting {
  static const startupWindowMs = 3000;
  static const transitionWindowMs = 2000;
  static const transitionAllowanceFrames = 5;

  int rawDroppedFrames = 0;
  int droppedFrames = 0;
  int recentDroppedFrames = 0;
  int get excludedDroppedFrames => rawDroppedFrames - droppedFrames;
  bool _startupPending = true;
  bool _longPressRecovery = false;
  int? _windowUntilMs;
  int _remainingAllowance = transitionAllowanceFrames;
  int _intervalFrames = 0;
  int _lastBackendTotal = 0;

  void reset() {
    rawDroppedFrames = droppedFrames = recentDroppedFrames = 0;
    _startupPending = true;
    _longPressRecovery = false;
    _windowUntilMs = null;
    _remainingAllowance = transitionAllowanceFrames;
    _intervalFrames = _lastBackendTotal = 0;
  }

  void firstFrame(int nowMs) {
    if (!_startupPending) return;
    _startupPending = false;
    _windowUntilMs = nowMs + startupWindowMs;
    // 首帧前后的起播共用五帧，首帧事件不能再次补满容差。
  }

  void speedTransition(int nowMs, {bool reuseAllowance = false}) {
    if (_startupPending) return;
    final reuse =
        reuseAllowance && _windowUntilMs != null && nowMs <= _windowUntilMs!;
    _windowUntilMs = nowMs + transitionWindowMs;
    // 后续重定位复用切速额度；松手恢复期间另由恢复窗口整体排除。
    if (!reuse) _remainingAllowance = transitionAllowanceFrames;
  }

  /// 控制器在松手前后采样，并在恢复期结束时先收取末次计数再关闭排除。
  void beginLongPressRecovery() {
    _longPressRecovery = true;
  }

  void endLongPressRecovery() {
    _longPressRecovery = false;
    // 恢复期已全部排除，退出切速和重定位的剩余额度不能再抵扣正常播放。
    _windowUntilMs = null;
    _remainingAllowance = 0;
  }

  void sample(
    int total, {
    required int nowMs,
    bool finishInterval = false,
    bool isPlaying = true,
    bool isBuffering = false,
  }) {
    if (total < 0) return;
    // 后端可在 seek 或重建输出时清零；历史总数只由显式新会话 reset 清除。
    var delta = total >= _lastBackendTotal ? total - _lastBackendTotal : total;
    _lastBackendTotal = total;
    rawDroppedFrames += delta;
    if (!isPlaying || isBuffering) {
      _intervalFrames = recentDroppedFrames = 0;
      // 暂停和缓冲不授予新的切速容差，恢复后继续正常计数。
      if (_windowUntilMs != null && nowMs > _windowUntilMs!) {
        _windowUntilMs = null;
        _remainingAllowance = 0;
      }
      return;
    }
    if (_longPressRecovery) {
      delta = 0;
    } else if (_startupPending || _windowUntilMs != null) {
      final excluded = math.min(delta, _remainingAllowance);
      delta -= excluded;
      _remainingAllowance -= excluded;
      if (_windowUntilMs != null && nowMs > _windowUntilMs!) {
        // 边界采样中的延迟上报仍受五帧总额约束，随后立即关闭窗口。
        _windowUntilMs = null;
        _remainingAllowance = 0;
      }
    }
    droppedFrames += delta;
    _intervalFrames += delta;
    if (finishInterval) {
      recentDroppedFrames = _intervalFrames;
      _intervalFrames = 0;
    } else if (delta > 0) {
      recentDroppedFrames = _intervalFrames;
    }
  }
}
