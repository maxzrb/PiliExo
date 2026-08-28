import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HDR 画质只在 Android 在线视频路由到 Media3', () {
    for (final code in [125, 126, 129]) {
      expect(
        HdrPlaybackPolicy.shouldUseMedia3(
          isAndroid: true,
          isLive: false,
          isFile: false,
          enabled: true,
          qualityCode: code,
        ),
        isTrue,
      );
    }

    expect(
      HdrPlaybackPolicy.shouldUseMedia3(
        isAndroid: true,
        isLive: true,
        isFile: false,
        enabled: true,
        qualityCode: 129,
      ),
      isFalse,
    );
    expect(
      HdrPlaybackPolicy.shouldUseMedia3(
        isAndroid: true,
        isLive: false,
        isFile: true,
        enabled: true,
        qualityCode: 129,
      ),
      isFalse,
    );
    expect(
      HdrPlaybackPolicy.shouldUseMedia3(
        isAndroid: false,
        isLive: false,
        isFile: false,
        enabled: true,
        qualityCode: 129,
      ),
      isFalse,
    );
    expect(
      HdrPlaybackPolicy.shouldUseMedia3(
        isAndroid: true,
        isLive: false,
        isFile: false,
        enabled: false,
        qualityCode: 129,
      ),
      isFalse,
    );
    expect(
      HdrPlaybackPolicy.shouldUseMedia3(
        isAndroid: true,
        isLive: false,
        isFile: false,
        enabled: true,
        qualityCode: VideoQuality.super4K.code,
      ),
      isFalse,
    );
  });

  test('HDR 源保留视频和音频的所有 URL', () {
    final video = HdrTrackSource(
      urls: const ['video-main', 'video-backup', 'video-main'],
      mimeType: 'video/mp4',
      codecs: 'hev1.2.4.L153',
      width: 3840,
      height: 2160,
      frameRate: '60',
    );
    final audio = HdrTrackSource(urls: const ['audio-main', 'audio-backup']);
    final source = HdrNetworkSource(
      qualityCode: 129,
      video: video,
      audio: audio,
    );

    expect(video.urls, ['video-main', 'video-backup']);
    expect(source.videoSource, 'video-main');
    expect(source.audioSource, 'audio-main');
    expect(source.qualityCode, 129);
  });
}
