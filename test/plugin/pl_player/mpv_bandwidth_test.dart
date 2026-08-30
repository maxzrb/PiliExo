import 'package:PiliPlus/plugin/pl_player/utils/mpv_bandwidth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放时按节流间隔读取 cache-speed', () {
    var reads = 0;
    final sampler = MpvBandwidthSampler((_) {
      reads++;
      return '1250000';
    });

    expect(sampler.sample(isPlaying: true, nowMs: 0), 10000000);
    expect(sampler.sample(isPlaying: true, nowMs: 100), 10000000);
    expect(reads, 1);
    expect(sampler.sample(isPlaying: true, nowMs: 250), 10000000);
    expect(reads, 2);
  });

  test('暂停时不再读取并保留最近一次有效带宽', () {
    var reads = 0;
    final sampler = MpvBandwidthSampler((_) {
      reads++;
      return reads == 1 ? '2000000' : '4000000';
    });

    expect(sampler.sample(isPlaying: true, nowMs: 0), 16000000);
    expect(sampler.sample(isPlaying: false, nowMs: 1000), 16000000);
    expect(reads, 1);
  });

  test('无效或零值不会覆盖已有估计，切换媒体后可重置', () {
    var value = '3000000';
    final sampler = MpvBandwidthSampler((_) => value);

    expect(sampler.sample(isPlaying: true, nowMs: 0), 24000000);
    value = '0';
    expect(sampler.sample(isPlaying: true, nowMs: 250), 24000000);
    value = 'not-a-number';
    expect(sampler.sample(isPlaying: true, nowMs: 500), 24000000);

    sampler.reset();
    expect(sampler.sample(isPlaying: false, nowMs: 750), isNull);
  });
}
