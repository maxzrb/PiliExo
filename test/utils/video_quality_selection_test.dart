import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:flutter_test/flutter_test.dart';

VideoItem _video(int quality, {int? codecid}) => VideoItem(
  id: quality,
  baseUrl: 'https://example.com/$quality.m4s',
  codecid: codecid,
  quality: VideoQuality.fromCode(quality),
);

PlayUrlModel _playUrl(Iterable<int> qualities) => PlayUrlModel(
  dash: Dash(video: qualities.map(_video).toList()),
);

void main() {
  group('PlayUrlModel.findAvailableVideoQuality', () {
    test('HDR Vivid 偏好不会因为画质码 129 大于 8K 的 127 而跳到 8K', () {
      final model = _playUrl([
        VideoQuality.super8k.code,
        VideoQuality.hdrVivid.code,
        VideoQuality.dolbyVision.code,
      ]);

      expect(
        model.findAvailableVideoQuality(VideoQuality.hdrVivid.code),
        VideoQuality.hdrVivid.code,
      );
    });

    test('偏好画质不可用时按设置页顺序向下选择', () {
      final model = _playUrl([
        VideoQuality.super8k.code,
        VideoQuality.dolbyVision.code,
        VideoQuality.hdr.code,
      ]);

      expect(
        model.findAvailableVideoQuality(VideoQuality.hdrVivid.code),
        VideoQuality.dolbyVision.code,
      );
    });

    test('8K 不可用时会按列表顺序降到 HDR Vivid，而不是依赖画质码大小', () {
      final model = _playUrl([
        VideoQuality.hdrVivid.code,
        VideoQuality.dolbyVision.code,
      ]);

      expect(
        model.findAvailableVideoQuality(VideoQuality.super8k.code),
        VideoQuality.hdrVivid.code,
      );
    });

    test('没有更低画质时仍回退到可播放的最高画质', () {
      final model = _playUrl([VideoQuality.super8k.code]);

      expect(
        model.findAvailableVideoQuality(VideoQuality.hdrVivid.code),
        VideoQuality.super8k.code,
      );
    });
  });

  test('能够找出需要补拉的缺失画质流', () {
    final model = PlayUrlModel(
      dash: Dash(
        video: [
          _video(VideoQuality.hdrVivid.code),
          _video(VideoQuality.dolbyVision.code),
        ],
      ),
      supportFormats: [
        FormatItem(quality: VideoQuality.super8k.code),
        FormatItem(quality: VideoQuality.hdrVivid.code),
        FormatItem(quality: VideoQuality.dolbyVision.code),
      ],
    );

    expect(
      model.missingVideoQualityBelowHighest,
      VideoQuality.super8k.code,
    );
  });
}
