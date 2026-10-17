import 'package:PiliPlus/plugin/pl_player/utils/decoder_operating_rate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int? plan(
    String? fps, {
    double base = 1,
    double temporary = 3,
    bool android = true,
    bool hardware = true,
    bool live = false,
    bool audioOnly = false,
  }) => DecoderOperatingRate.plan(
    isAndroid: android,
    hardwareEnabled: hardware,
    isLive: live,
    audioOnly: audioOnly,
    frameRate: fps,
    baseRate: base,
    temporaryRate: temporary,
  );

  test('按素材帧率规划需求，不把所有视频固定为180', () {
    expect(plan('30'), 90);
    expect(plan('60'), 180);
    expect(plan('24'), 72);
    expect(plan('60000/1001'), 180);
    expect(plan('30000/1001'), 90);
  });

  test('基础速度高于临时速度时仍满足基础需求', () {
    expect(plan('60', base: 1.5, temporary: 1), 90);
    expect(plan('60', base: 2, temporary: 4), 240);
  });

  test('未知或异常帧率保留原解码策略', () {
    for (final value in [
      null,
      '',
      'unknown',
      '0',
      '-30',
      '60/0',
      'NaN',
      'Infinity',
      '300',
      '60/1/1',
    ]) {
      expect(plan(value), isNull, reason: '$value');
    }
  });

  test('桌面、软解、直播和听视频不额外申请视频资源', () {
    expect(plan('60', android: false), isNull);
    expect(plan('60', hardware: false), isNull);
    expect(plan('60', live: true), isNull);
    expect(plan('60', audioOnly: true), isNull);
  });

  test('异常倍速不生成无效的解码参数', () {
    expect(plan('60', base: double.nan), isNull);
    expect(plan('60', temporary: double.infinity), isNull);
    expect(plan('60', temporary: 0), isNull);
  });
}
