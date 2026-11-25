/// 片尾冻结后拖动进度条时的播放意图。
abstract final class PlaybackSeekPolicy {
  static const endTolerance = Duration(milliseconds: 250);

  static bool shouldResumeAfterCompletedSeek({
    required bool isLive,
    required bool wasCompleted,
    required bool playWhenReady,
    required Duration target,
    required Duration duration,
  }) {
    if (isLive || !wasCompleted || playWhenReady) return false;
    if (duration <= endTolerance) return false;
    return target < duration - endTolerance;
  }

  /// 播放器位置真正越过 seek 目标后，片尾拖回事务才算完成。
  ///
  /// 不能只依赖 seek 请求的完成回调，部分后端会先回写旧片尾事件，再回写新位置。
  static bool hasAdvancedFromCompletedSeek({
    required Duration observed,
    required Duration target,
    required Duration duration,
  }) {
    if (duration <= endTolerance) return false;
    if (target >= duration - endTolerance) return false;
    return observed > target && observed < duration - endTolerance;
  }
}
