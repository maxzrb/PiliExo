/// 两种播放器共用的带宽估计刷新器。
///
/// 输入和输出都使用比特/秒；不做跨样本平滑，只限制读取/展示节奏，并保留最近值。
class BandwidthEstimateSampler {
  static const sampleIntervalMs = 1000;

  int? _lastSampleAtMs;
  num? _lastBitsPerSecond;

  num? sample({
    num? bitsPerSecond,
    num? Function()? readBitsPerSecond,
    required bool isPlaying,
    int? nowMs,
  }) {
    if (!isPlaying) return _lastBitsPerSecond;

    final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final lastSampleAt = _lastSampleAtMs;
    if (lastSampleAt != null && timestamp - lastSampleAt < sampleIntervalMs) {
      return _lastBitsPerSecond;
    }
    _lastSampleAtMs = timestamp;

    bitsPerSecond ??= readBitsPerSecond?.call();
    if (bitsPerSecond != null && bitsPerSecond >= 0 && bitsPerSecond.isFinite) {
      _lastBitsPerSecond = bitsPerSecond;
    }
    return _lastBitsPerSecond;
  }

  void reset() {
    _lastSampleAtMs = null;
    _lastBitsPerSecond = null;
  }
}

/// mpv 播放器带宽估计采样器。
///
/// [cache-speed] 的单位是字节/秒，采样器返回统一 Telemetry 使用的比特/秒。
/// 该属性是缓存与下层之间 1 秒窗口的 I/O 读速率，缓存预取时会出现短时峰值，
/// 不能等同于链路测速；这里只转换单位后交给公共刷新器直接展示。
class MpvBandwidthSampler {
  MpvBandwidthSampler(this._readProperty);

  static const _property = 'cache-speed';

  final String Function(String property) _readProperty;
  final _sampler = BandwidthEstimateSampler();

  num? sample({required bool isPlaying, int? nowMs}) {
    return _sampler.sample(
      isPlaying: isPlaying,
      nowMs: nowMs,
      readBitsPerSecond: () {
        try {
          final value = num.tryParse(_readProperty(_property).trim());
          if (value != null && value >= 0 && value.isFinite) {
            return value * 8;
          }
        } catch (_) {
          // 属性在播放器切换媒体或释放期间可能暂时不可读，保留上一次结果。
        }
        return null;
      },
    );
  }

  void reset() => _sampler.reset();
}
