import 'package:PiliPlus/models/common/video/audio_quality.dart';

/// 音频音轨选择工具。
abstract final class AudioTrackSelector {
  /// 自动选择时使用的语义优先级。
  ///
  /// 音频 ID 只是服务端标识，不能通过数值大小推断音质高低。
  static final List<AudioQuality> _autoPriority = List.unmodifiable([
    AudioQuality.hiRes,
    AudioQuality.dolby_30250,
    AudioQuality.dolby_30255,
    AudioQuality.k192,
    AudioQuality.k132,
    AudioQuality.k64,
  ]);

  /// 从实际可用音轨中选择音轨。
  ///
  /// 当目标音质存在时保留用户的目标设置；目标不存在时，按明确的音质
  /// 优先级选择可用音轨。未识别的音轨只作为最后兜底，并保持服务端顺序。
  static T select<T>({
    required Iterable<T> tracks,
    required int? Function(T track) idOf,
    int? preferredId,
  }) {
    final availableTracks = tracks.toList(growable: false);
    if (availableTracks.isEmpty) {
      throw StateError('音轨列表不能为空');
    }

    if (preferredId != null) {
      for (final track in availableTracks) {
        if (idOf(track) == preferredId) return track;
      }
    }

    for (final quality in _autoPriority) {
      for (final track in availableTracks) {
        if (idOf(track) == quality.code) return track;
      }
    }

    return availableTracks.first;
  }
}
