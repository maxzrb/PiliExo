import 'package:PiliPlus/plugin/pl_player/utils/mpv_bandwidth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Media3 比特/秒输入复用相同的刷新节拍并直接显示原值', () {
    final sampler = BandwidthEstimateSampler();

    expect(
      sampler.sample(bitsPerSecond: 300000000, isPlaying: true, nowMs: 0),
      300000000,
    );
    expect(
      sampler.sample(bitsPerSecond: 100000000, isPlaying: true, nowMs: 500),
      300000000,
    );
    expect(
      sampler.sample(bitsPerSecond: 100000000, isPlaying: true, nowMs: 1000),
      100000000,
    );
  });

  test('播放时按节流间隔读取 cache-speed', () {
    var reads = 0;
    final sampler = MpvBandwidthSampler((_) {
      reads++;
      return '1250000';
    });

    expect(sampler.sample(isPlaying: true, nowMs: 0), 10000000);
    expect(sampler.sample(isPlaying: true, nowMs: 500), 10000000);
    expect(reads, 1);
    expect(sampler.sample(isPlaying: true, nowMs: 1000), 10000000);
    expect(reads, 2);
  });

  test('暂停时不再读取并保留最近一次有效带宽', () {
    var reads = 0;
    final sampler = MpvBandwidthSampler((_) {
      reads++;
      return reads == 1 ? '2000000' : '4000000';
    });

    expect(sampler.sample(isPlaying: true, nowMs: 0), 16000000);
    expect(sampler.sample(isPlaying: false, nowMs: 2000), 16000000);
    expect(reads, 1);
  });

  test('无效值和零值不会覆盖已有估计', () {
    var value = '3000000';
    final sampler = MpvBandwidthSampler((_) => value);

    expect(sampler.sample(isPlaying: true, nowMs: 0), 24000000);
    value = '0';
    expect(sampler.sample(isPlaying: true, nowMs: 1000), 24000000);
    value = 'not-a-number';
    expect(sampler.sample(isPlaying: true, nowMs: 2000), 24000000);

    value = 'not-a-number';
    expect(sampler.sample(isPlaying: true, nowMs: 3000), 24000000);
  });

  test('首次只有零值时仍保持未测量状态', () {
    final sampler = MpvBandwidthSampler((_) => '0');

    expect(sampler.sample(isPlaying: true, nowMs: 0), isNull);
  });

  test('切换媒体后清空历史样本', () {
    final sampler = MpvBandwidthSampler((_) => '3000000');

    expect(sampler.sample(isPlaying: true, nowMs: 0), 24000000);

    sampler.reset();
    expect(sampler.sample(isPlaying: false, nowMs: 1000), isNull);
  });
}
