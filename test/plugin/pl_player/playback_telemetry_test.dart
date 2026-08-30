import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('洞察详情展示 Media3 实际视频与音频诊断数据', () {
    final snapshot = PlaybackInsightSnapshot.fromTelemetry(
      PlaybackTelemetry(
        engine: 'Media3 原生 HDR',
        quality: '129',
        representation: 'video-0 · q=129 · 3840x2160 · dvhe.08.06',
        representationId: 'video-0',
        resolution: '3840×2160',
        videoCodec: 'Dolby Vision',
        videoCodecString: 'dvhe.08.06',
        videoProfile: '4096',
        videoLevel: '256',
        dolbyVisionProfile: '08',
        dolbyVisionLevel: '06',
        hdrType: 'Dolby Vision',
        videoMimeType: 'video/dolby-vision',
        frameRate: '60.00 fps',
        videoDecoder: 'c2.qti.dolby.decoder',
        videoDecoderType: '硬解',
        videoBitrate: '12.00 Mbps',
        audioCodec: 'E-AC-3',
        audioCodecString: 'ec-3',
        audioMimeType: 'audio/eac3',
        audioSampleRate: '48000 Hz',
        audioChannelCount: '6',
        audioChannelLayout: '0x3F',
        audioDecoder: 'c2.android.eac3.decoder',
        audioDecoderType: '硬解',
        audioBitrate: '192 kbps',
        cdnHost: 'cdn.example.com',
        bandwidthEstimate: '30.00 Mbps',
        droppedFrames: 3,
        recentDroppedFrames: 1,
      ),
    );

    expect(
      snapshot.videoRows.any(
        (row) => row.label == '视频 Codec' && row.value == 'Dolby Vision',
      ),
      isTrue,
    );
    expect(
      snapshot.videoRows.any(
        (row) => row.label == 'Codec String' && row.value == 'dvhe.08.06',
      ),
      isTrue,
    );
    expect(
      snapshot.videoRows.any(
        (row) => row.label == 'Dolby Vision Profile' && row.value == '08',
      ),
      isTrue,
    );
    expect(
      snapshot.videoRows.any(
        (row) => row.label == '视频码率' && row.value == '12.00 Mbps',
      ),
      isTrue,
    );
    expect(
      snapshot.audioRows.any(
        (row) => row.label == '采样率' && row.value == '48000 Hz',
      ),
      isTrue,
    );
    expect(
      snapshot.audioRows.any(
        (row) => row.label == '声道布局' && row.value == '0x3F',
      ),
      isTrue,
    );
    expect(
      snapshot.overviewRows.any(
        (row) => row.label == '视频码率' && row.value == '12.00 Mbps',
      ),
      isTrue,
    );
    expect(
      snapshot.overviewRows.any((row) => row.label == '当前 Representation'),
      isFalse,
    );
  });

  test('概览不重复展示冗长 Representation 内容', () {
    final snapshot = PlaybackInsightSnapshot(
      representation: 'video-0 · q=129 · 3840x2160 · dvhe.08.06',
      representationId: 'video-0',
      quality: '129',
      resolution: '3840×2160',
      videoCodec: 'Dolby Vision',
      videoCodecString: 'dvhe.08.06',
    );

    expect(
      snapshot.overviewRows.map((row) => row.label),
      isNot(contains('当前 Representation')),
    );
    expect(
      snapshot.videoRows.map((row) => row.label),
      contains('Codec String'),
    );
    expect(snapshot.overviewRows.map((row) => row.label), contains('分辨率'));
  });

  test('Representation fallback 历史可被洞察页读取', () {
    final record = const PlaybackFallbackRecord(
      from: 'video-0',
      to: 'video-1',
      reason: 'ERROR_CODE_DECODER_INIT_FAILED',
      errorCode: '4001',
      message: 'decoder init failed',
    );
    final snapshot = PlaybackInsightSnapshot.fromTelemetry(
      PlaybackTelemetry(
        fallbackReason: 'ERROR_CODE_DECODER_INIT_FAILED',
        fallbackHistory: [record],
      ),
    );

    expect(snapshot.fallbackRows.single.value, contains('video-0 → video-1'));
    expect(snapshot.fallbackRows.single.value, contains('4001'));
  });

  test('HDR 数据源始终至少保留主 Representation', () {
    final source = HdrNetworkSource(
      qualityCode: 129,
      video: HdrTrackSource(urls: ['https://cdn.example.com/video.m4s']),
      videoRepresentations: const [],
    );

    expect(source.videoRepresentations, hasLength(1));
    expect(source.videoRepresentations.single.id, 'primary');
  });
}
