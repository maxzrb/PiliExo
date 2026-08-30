import 'package:PiliPlus/models/common/video/audio_quality.dart';
import 'package:PiliPlus/utils/audio_track_selector.dart';
import 'package:flutter_test/flutter_test.dart';

class _AudioTrack {
  const _AudioTrack(this.id);

  final int id;
}

void main() {
  _AudioTrack select(List<int> ids, {int? preferredId}) {
    return AudioTrackSelector.select(
      tracks: ids.map(_AudioTrack.new),
      preferredId: preferredId,
      idOf: (track) => track.id,
    );
  }

  test('目标音质存在时优先使用目标音质', () {
    final track = select([
      AudioQuality.hiRes.code,
      AudioQuality.k132.code,
    ], preferredId: AudioQuality.k132.code);

    expect(track.id, AudioQuality.k132.code);
  });

  test('目标音质不存在时按明确优先级选择实际可用音轨', () {
    final track = select([
      AudioQuality.k64.code,
      AudioQuality.dolby_30255.code,
      AudioQuality.dolby_30250.code,
      AudioQuality.hiRes.code,
      AudioQuality.k132.code,
    ], preferredId: AudioQuality.k192.code);

    expect(track.id, AudioQuality.hiRes.code);
  });

  test('Dolby Atmos 优先于 Dolby Audio，且不按 ID 数值排序', () {
    final track = select([
      AudioQuality.dolby_30255.code,
      AudioQuality.dolby_30250.code,
    ], preferredId: AudioQuality.k192.code);

    expect(track.id, AudioQuality.dolby_30250.code);
  });

  test('普通音质按 192K、132K、64K 顺序选择', () {
    final track = select([
      AudioQuality.k64.code,
      AudioQuality.k132.code,
      AudioQuality.k192.code,
    ], preferredId: AudioQuality.hiRes.code);

    expect(track.id, AudioQuality.k192.code);
  });

  test('仅有 Dolby 音轨时不会错误回退到 192K', () {
    final atmos = select([
      AudioQuality.dolby_30250.code,
    ], preferredId: AudioQuality.k192.code);
    final dolbyAudio = select([
      AudioQuality.dolby_30255.code,
    ], preferredId: AudioQuality.k192.code);

    expect(atmos.id, AudioQuality.dolby_30250.code);
    expect(dolbyAudio.id, AudioQuality.dolby_30255.code);
  });

  test('没有已知音质时保持服务端顺序兜底', () {
    final track = select([100010, 100009], preferredId: AudioQuality.k192.code);

    expect(track.id, 100010);
  });
}
