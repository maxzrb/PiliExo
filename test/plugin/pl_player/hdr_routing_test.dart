import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
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

  test('HDR 画面模式映射到 Media3 支持的 resize mode', () {
    expect(VideoFitType.fill.hdrResizeMode, 'fill');
    expect(VideoFitType.cover.hdrResizeMode, 'cover');
    expect(VideoFitType.fitWidth.hdrResizeMode, 'fitWidth');
    expect(VideoFitType.fitHeight.hdrResizeMode, 'fitHeight');
    expect(VideoFitType.contain.hdrResizeMode, 'fit');
  });

  test('HDR 固定画幅模式保留 4:3 和 16:9 约束', () {
    expect(VideoFitType.ratio_4x3.hdrResizeMode, 'fit');
    expect(VideoFitType.ratio_4x3.aspectRatio, closeTo(4 / 3, 0.000001));
    expect(VideoFitType.ratio_16x9.hdrResizeMode, 'fit');
    expect(
      VideoFitType.ratio_16x9.aspectRatio,
      closeTo(16 / 9, 0.000001),
    );
  });

  test('mpv 输出未就绪时不挂载播放器，HDR 输出可独立挂载', () {
    expect(
      VideoOutputPolicy.shouldBuildPlayer(
        videoState: true,
        autoPlay: true,
        outputReady: false,
        isMedia3Hdr: false,
      ),
      isFalse,
    );
    expect(
      VideoOutputPolicy.shouldBuildPlayer(
        videoState: true,
        autoPlay: true,
        outputReady: true,
        isMedia3Hdr: false,
      ),
      isTrue,
    );
    expect(
      VideoOutputPolicy.shouldBuildPlayer(
        videoState: true,
        autoPlay: true,
        outputReady: false,
        isMedia3Hdr: true,
      ),
      isTrue,
    );
  });
}
