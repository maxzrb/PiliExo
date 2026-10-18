import 'dart:math' as math;

/// 起播和每次切速最多排除五帧，其他播放丢帧立即计入洞察。
/// 复用既有采样，保留原始计数，不根据后端计数断言设备故障。
class PlaybackDropAccounting {
  static const startupWindowMs = 3000;
  static const transitionWindowMs = 2000;
  static const transitionAllowanceFrames = 5;

  int rawDroppedFrames = 0;
  int droppedFrames = 0;
  int recentDroppedFrames = 0;
  int get excludedDroppedFrames => rawDroppedFrames - droppedFrames;
  bool _startupPending = true;
  int? _windowUntilMs;
  int _remainingAllowance = transitionAllowanceFrames;
  int _intervalFrames = 0;

  void reset() {
    rawDroppedFrames = droppedFrames = recentDroppedFrames = 0;
    _startupPending = true;
    _windowUntilMs = null;
    _remainingAllowance = transitionAllowanceFrames;
    _intervalFrames = 0;
  }

  void firstFrame(int nowMs) {
    if (!_startupPending) return;
    _startupPending = false;
    _windowUntilMs = nowMs + startupWindowMs;
    // 首帧前后的起播共用五帧，首帧事件不能再次补满容差。
  }

  void speedTransition(int nowMs) {
    if (_startupPending) return;
    _windowUntilMs = nowMs + transitionWindowMs;
    // 进入与退出倍速各有五帧；未使用的额度不叠加到下一次切速。
    _remainingAllowance = transitionAllowanceFrames;
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
      // 切源或后端计数重置时不继承旧异常和容差。
      reset();
      firstFrame(nowMs);
    }
    var delta = total - rawDroppedFrames;
    rawDroppedFrames = total;
    if (!isPlaying || isBuffering) {
      _intervalFrames = recentDroppedFrames = 0;
      // 暂停和缓冲不授予新的切速容差，恢复后继续正常计数。
      if (_windowUntilMs != null && nowMs > _windowUntilMs!) {
        _windowUntilMs = null;
        _remainingAllowance = 0;
      }
      return;
    }
    if (_startupPending || _windowUntilMs != null) {
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
