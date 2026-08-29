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
      snapshot.audioRows.any(
        (row) => row.label == '音频码率' && row.value == '192 kbps',
      ),
      isTrue,
    );
  });
}
