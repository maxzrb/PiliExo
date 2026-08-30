/// mpv 播放器带宽估计采样器。
///
/// [cache-speed] 的单位是字节/秒，采样器返回统一 Telemetry 使用的比特/秒。
/// 采样器只在播放状态读取属性，暂停后保留最近一次有效值，避免暂停期间继续
/// 计算或让洞察里的数值跳动。
class MpvBandwidthSampler {
  MpvBandwidthSampler(this._readProperty);

  static const sampleIntervalMs = 250;
  static const _property = 'cache-speed';

  final String Function(String property) _readProperty;
  int? _lastSampleAtMs;
  num? _lastBitsPerSecond;

  num? sample({required bool isPlaying, int? nowMs}) {
    if (!isPlaying) return _lastBitsPerSecond;

    final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final lastSampleAt = _lastSampleAtMs;
    if (lastSampleAt != null && timestamp - lastSampleAt < sampleIntervalMs) {
      return _lastBitsPerSecond;
    }
    _lastSampleAtMs = timestamp;

    try {
      final value = num.tryParse(_readProperty(_property).trim());
      if (value != null && value > 0 && value.isFinite) {
        _lastBitsPerSecond = value * 8;
      }
    } catch (_) {
      // 属性在播放器切换媒体或释放期间可能暂时不可读，保留上一次结果。
    }
    return _lastBitsPerSecond;
  }

  void reset() {
    _lastSampleAtMs = null;
    _lastBitsPerSecond = null;
  }
}
