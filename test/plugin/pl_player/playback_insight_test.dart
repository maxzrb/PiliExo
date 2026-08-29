import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放器洞察视频详情包含视频码率', () {
    const snapshot = PlaybackInsightSnapshot(
      videoBitrate: '5.00 Mbps',
      audioBitrate: '192 kbps',
    );

    expect(
      snapshot.videoRows.any(
        (row) => row.label == '视频码率' && row.value == '5.00 Mbps',
      ),
      isTrue,
    );
    expect(
      snapshot.overviewRows.any(
        (row) => row.label == '视频码率' && row.value == '5.00 Mbps',
      ),
      isTrue,
    );
    expect(
      snapshot.audioRows.any(
        (row) => row.label == '音频码率' && row.value == '192 kbps',
      ),
      isTrue,
    );
  });

  test('DASH 轨道码率会传入播放器数据源作为回退值', () {
    final source = HdrNetworkSource(
      qualityCode: 125,
      video: HdrTrackSource(
        urls: ['https://example.com/video.m4s'],
        bitrate: 5000000,
      ),
      audio: HdrTrackSource(
        urls: ['https://example.com/audio.m4s'],
        bitrate: 192000,
      ),
    );

    expect(source.videoBitrate, 5000000);
    expect(source.audioBitrate, 192000);
    expect(source.video.toJson()['bitrate'], 5000000);

    final fallbackSource = NetworkSource(
      videoSource: 'https://example.com/video.mp4',
      audioSource: null,
      videoBitrate: 5000000,
    );
    expect(fallbackSource.videoBitrate, 5000000);
  });
}
