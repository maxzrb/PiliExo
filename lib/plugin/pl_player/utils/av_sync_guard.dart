/// 长按倍速结束后的音画差保护。
///
/// 1 秒内的落后交给播放器自行追帧；超过后按音频时钟快速重定位，
/// 避免松手后持续几十秒的大幅丢帧。
abstract final class AvSyncGuard {
  static const maxCatchUpSeconds = 1.0;

  static bool needsSeek(double? avsync) =>
      avsync != null && avsync.isFinite && avsync > maxCatchUpSeconds;
}
