import 'package:PiliPlus/models/common/video/audio_quality.dart';
import 'package:PiliPlus/models/common/video/live_quality.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未知服务端画质和音质编码保留编码而不崩溃或伪装成默认档位', () {
    expect(VideoQuality.fromCode(999).code, 999);
    expect(VideoQuality.fromCode(999).desc, '999');
    expect(AudioQuality.fromCode(999).code, 999);
    expect(LiveQuality.fromCode(999).code, 999);
    expect(VideoQuality.fromCode(100), VideoQuality.superResolution);
  });
  test('服务端新画质使用对应描述，缺字段时仍可安全降级显示', () {
    final format = FormatItem(quality: 999, newDesc: '新画质', displayDesc: '新');
    expect(VideoQuality.fromFormat(999, [format]).shortDesc, '新');
    expect(VideoQuality.fromFormat(999, [FormatItem(quality: 999)]).code, 999);
  });
  test('保留本地8K优先顺序和三种HDR分类', () {
    expect(VideoQuality.values.first, VideoQuality.super8k);
    for (final code in [125, 126, 129]) {
      expect(VideoQuality.fromCode(code).isHdr, isTrue);
    }
    expect(VideoQuality.high108060.isHdr, isFalse);
    expect(VideoQuality.fromCode(999).isHdr, isFalse);
  });
  test('直播新档位优先使用服务端说明', () {
    final format = LiveQuality.fromJson({'qn': 999, 'desc': '测试档位'});
    expect(LiveQuality.fromFormat(999, [format]).desc, '测试档位');
    expect(LiveQuality.fromFormat(999, null).desc, '999');
  });
}
