import 'package:PiliPlus/plugin/pl_player/utils/media_bitrate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('媒体消耗带宽等于当前视频和音频轨道码率之和', () {
    expect(MediaBitrate.sum(5000000, 192000), 5192000);
  });

  test('缺失或无效轨道码率不会污染媒体消耗带宽', () {
    expect(MediaBitrate.sum(5000000, null), 5000000);
    expect(MediaBitrate.sum(null, 192000), 192000);
    expect(MediaBitrate.sum(double.nan, double.infinity), isNull);
    expect(MediaBitrate.sum(0, -1), isNull);
  });

  test('mpv 使用当前媒体缓存窗口的字节数和时长计算码率', () {
    final values = <String, String>{
      'demuxer-cache-state/fw-bytes': '650000',
      'demuxer-cache-state/cache-duration': '1',
    };
    final sampler = MpvMediaBitrateSampler((property) => values[property]!);

    expect(
      sampler.sample(
        isPlaying: true,
        fallbackBitsPerSecond: 5192000,
        nowMs: 0,
      ),
      5200000,
    );

    values['demuxer-cache-state/fw-bytes'] = '900000';
    values['demuxer-cache-state/cache-duration'] = '2';
    expect(
      sampler.sample(
        isPlaying: true,
        fallbackBitsPerSecond: 5192000,
        nowMs: 500,
      ),
      5200000,
    );
    expect(
      sampler.sample(
        isPlaying: true,
        fallbackBitsPerSecond: 5192000,
        nowMs: 1000,
      ),
      3600000,
    );
  });

  test('mpv 媒体缓存数据不可用时回退到轨道总码率', () {
    final sampler = MpvMediaBitrateSampler((_) => '0');

    expect(
      sampler.sample(
        isPlaying: true,
        fallbackBitsPerSecond: 5192000,
        nowMs: 0,
      ),
      5192000,
    );
  });
}
