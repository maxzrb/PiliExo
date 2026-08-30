/// 播放器侧滑调节的刻度震动配置。
const int kDefaultGestureHapticStepPercent = 3;
const int kMinGestureHapticStepPercent = 1;
const int kMaxGestureHapticStepPercent = 20;
const double _gestureHapticFloatingPointEpsilon = 0.000001;

int normalizeGestureHapticStepPercent(int value) => value
    .clamp(kMinGestureHapticStepPercent, kMaxGestureHapticStepPercent)
    .toInt();

/// 记录一次连续手势中已经反馈过的百分比距离，避免按每 1% 触发震动。
class GestureHapticTickTracker {
  double? _lastFeedbackPercent;
  int _stepPercent = kDefaultGestureHapticStepPercent;

  void begin(
    double percent, {
    int stepPercent = kDefaultGestureHapticStepPercent,
  }) {
    _stepPercent = normalizeGestureHapticStepPercent(stepPercent);
    _lastFeedbackPercent = percent.isFinite ? percent : null;
  }

  /// 当本次手势相对上次震动累计跨过一个或多个刻度时返回 true。
  bool update(
    double percent, {
    int stepPercent = kDefaultGestureHapticStepPercent,
  }) {
    if (!percent.isFinite) return false;
    final normalizedStep = normalizeGestureHapticStepPercent(stepPercent);
    if (_lastFeedbackPercent == null || _stepPercent != normalizedStep) {
      begin(percent, stepPercent: normalizedStep);
      return false;
    }

    final delta = percent - _lastFeedbackPercent!;
    // 音量/亮度来自连续的浮点运算，刚好跨过刻度时可能会得到
    // 2.999999999% 之类的结果，允许极小误差避免漏掉本应触发的震动。
    final crossedSteps =
        ((delta.abs() + _gestureHapticFloatingPointEpsilon) /
                normalizedStep)
            .floor();
    if (crossedSteps < 1) return false;

    _lastFeedbackPercent =
        _lastFeedbackPercent! + delta.sign * normalizedStep * crossedSteps;
    return true;
  }

  void reset() {
    _lastFeedbackPercent = null;
  }
}
