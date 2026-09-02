/// 计算视频轨道与音频轨道的标称总码率。
abstract final class MediaBitrate {
  static num? sum(num? videoBitrate, num? audioBitrate) {
    final video = _valid(videoBitrate) ?? 0;
    final audio = _valid(audioBitrate) ?? 0;
    final total = video + audio;
    return total > 0 ? total : null;
  }

  static num? _valid(num? bitrate) {
    if (bitrate == null || bitrate <= 0 || !bitrate.isFinite) return null;
    return bitrate;
  }
}

/// 根据播放器当前媒体缓存窗口估算实际媒体消耗带宽。
///
/// [demuxer-cache-state/fw-bytes] 是当前解码位置之后已缓存媒体包的字节数，
/// [demuxer-cache-state/cache-duration] 是同一窗口覆盖的媒体时长。两者相除
/// 得到的是媒体内容码率，不会把 [cache-speed] 的网络下载突发直接展示出来。
class MpvMediaBitrateSampler {
  MpvMediaBitrateSampler(this._readProperty);

  static const sampleIntervalMs = 1000;
  static const _bytesProperty = 'demuxer-cache-state/fw-bytes';
  static const _durationProperty = 'demuxer-cache-state/cache-duration';

  final String Function(String property) _readProperty;
  int? _lastSampleAtMs;
  num? _lastBitsPerSecond;

  num? sample({
    required bool isPlaying,
    required num? fallbackBitsPerSecond,
    int? nowMs,
  }) {
    final fallback = _valid(fallbackBitsPerSecond);
    if (!isPlaying) return _lastBitsPerSecond ?? fallback;

    final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final lastSampleAt = _lastSampleAtMs;
    if (lastSampleAt != null && timestamp - lastSampleAt < sampleIntervalMs) {
      return _lastBitsPerSecond ?? fallback;
    }
    _lastSampleAtMs = timestamp;

    final bytes = _readNumber(_bytesProperty);
    final durationSeconds = _readNumber(_durationProperty);
    final estimate = bytes == null || durationSeconds == null
        ? null
        : _valid(bytes * 8 / durationSeconds);
    if (estimate != null) _lastBitsPerSecond = estimate;
    return _lastBitsPerSecond ?? fallback;
  }

  void reset() {
    _lastSampleAtMs = null;
    _lastBitsPerSecond = null;
  }

  num? _readNumber(String property) {
    try {
      return _valid(num.tryParse(_readProperty(property).trim()));
    } catch (_) {
      // 播放器切换媒体或释放期间属性可能暂时不可读，交给回退码率处理。
      return null;
    }
  }

  static num? _valid(num? value) {
    if (value == null || value <= 0 || !value.isFinite) return null;
    return value;
  }
}
