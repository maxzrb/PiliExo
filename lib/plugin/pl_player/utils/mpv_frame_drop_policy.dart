/// 原生 HDR 的解码及输出丢帧统一由 mpv 根据实际音频时钟控制。
abstract final class MpvFrameDropPolicy {
  static bool _isNormalSpeed(double speed) => !speed.isFinite || speed <= 1.01;

  static String optionFor({
    required bool nativeHdr,
    required bool hdrCompatibility,
    required double speed,
  }) {
    if (nativeHdr) return 'decoder+late';
    if (!_isNormalSpeed(speed)) return 'decoder';
    // HDR 转换走兼容纹理时，避免输出层按超时连续丢掉已解码画面。
    return hdrCompatibility ? 'no' : 'vo';
  }
}
