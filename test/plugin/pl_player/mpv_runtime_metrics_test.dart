import 'package:PiliPlus/plugin/pl_player/utils/mpv_runtime_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未报告的掉帧保持未知，收到零值后才是已测零掉帧', () {
    final metrics = MpvRuntimeMetrics()..finishSample();
    expect(metrics.droppedFramesAvailable, isFalse);
    metrics
      ..outputDroppedFrames = 0
      ..finishSample();
    expect(metrics.droppedFramesAvailable, isTrue);
    expect(metrics.droppedFrames, 0);
  });

  test('VO 丢帧按增量累计，重复采样不重复累加', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 2
      ..finishSample();
    expect(metrics.droppedFrames, 2);
    expect(metrics.recentDroppedFrames, 2);

    metrics
      ..outputDroppedFrames = 7
      ..finishSample();
    expect(metrics.droppedFrames, 7);
    expect(metrics.recentDroppedFrames, 5);
    metrics.finishSample();
    expect(metrics.recentDroppedFrames, 0);
  });

  test('输出层已由 mpv 扣除主动替换的过期帧', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 3
      ..finishSample();
    expect(metrics.droppedFrames, 3);
    expect(metrics.recentDroppedFrames, 3);

    metrics
      ..outputDroppedFrames = 6
      ..finishSample();
    expect(metrics.droppedFrames, 6);
    expect(metrics.recentDroppedFrames, 3);
  });

  test('mpv 解码估算的变化不计入播放器洞察', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 0
      ..decoderDroppedFrames = 40
      ..finishSample();
    expect(metrics.droppedFramesAvailable, isTrue);
    expect(metrics.droppedFrames, 0);
    expect(metrics.recentDroppedFrames, 0);

    metrics
      ..decoderDroppedFrames = 90
      ..finishSample();
    expect(metrics.droppedFrames, 0);
    expect(metrics.recentDroppedFrames, 0);
  });

  test('VO 丢帧计数独立累计', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 4
      ..finishSample();
    expect(metrics.droppedFrames, 4);

    metrics
      ..outputDroppedFrames = 9
      ..finishSample();

    expect(metrics.droppedFrames, 9);
    expect(metrics.recentDroppedFrames, 5);
  });

  test('计数回退后重新建立基线，不产生负数或虚假大增量', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 100
      ..finishSample();
    expect(metrics.droppedFrames, 100);

    metrics
      ..outputDroppedFrames = 0
      ..finishSample();
    expect(metrics.recentDroppedFrames, 0);
    metrics
      ..outputDroppedFrames = 3
      ..finishSample();
    expect(metrics.recentDroppedFrames, 3);
    expect(metrics.droppedFrames, 103);
  });

  test('mpv 解码估算清零或增长不改变 VO 丢帧累计', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 100
      ..decoderDroppedFrames = 10
      ..finishSample();
    expect(metrics.droppedFrames, 100);

    metrics
      ..outputDroppedFrames = 0
      ..decoderDroppedFrames = 13
      ..finishSample();
    expect(metrics.droppedFrames, 100);
    expect(metrics.recentDroppedFrames, 0);

    metrics
      ..outputDroppedFrames = 2
      ..decoderDroppedFrames = 0
      ..finishSample();
    expect(metrics.droppedFrames, 102);
    expect(metrics.recentDroppedFrames, 2);

    metrics
      ..decoderDroppedFrames = 4
      ..finishSample();
    expect(metrics.droppedFrames, 102);
    expect(metrics.recentDroppedFrames, 0);
  });

  test('属性暂时未知或无效时不清基线，恢复后只计算新增值', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 100
      ..finishSample();
    expect(metrics.droppedFrames, 100);

    metrics
      ..outputDroppedFrames = null
      ..finishSample();
    expect(metrics.droppedFrames, 100);
    expect(metrics.recentDroppedFrames, 0);

    metrics
      ..outputDroppedFrames = -1
      ..finishSample();
    expect(metrics.droppedFrames, 100);

    metrics
      ..outputDroppedFrames = 102
      ..finishSample();
    expect(metrics.droppedFrames, 102);
    expect(metrics.recentDroppedFrames, 2);
  });

  test('媒体带宽来自缓存窗口，未知或无效窗口不伪造测量', () {
    final metrics = MpvRuntimeMetrics();
    expect(metrics.mediaBitsPerSecond, isNull);
    metrics
      ..forwardBytes = 1000000
      ..cacheDuration = 2;
    expect(metrics.mediaBitsPerSecond, 4000000);
    for (final duration in [0.0, -1.0, double.nan, double.infinity]) {
      metrics.cacheDuration = duration;
      expect(metrics.mediaBitsPerSecond, isNull);
    }
  });
}
