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

  test('汇总输出与解码掉帧，增量不会被普通界面读取消耗', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 2
      ..decoderDroppedFrames = 1
      ..finishSample();
    metrics
      ..outputDroppedFrames = 7
      ..finishSample();
    expect(metrics.droppedFrames, 8);
    expect(metrics.recentDroppedFrames, 5);
    expect(metrics.recentDroppedFrames, 5);
    metrics.finishSample();
    expect(metrics.recentDroppedFrames, 0);
  });

  test('计数回退后重新建立基线，不产生负数或虚假大增量', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 100
      ..finishSample();
    metrics
      ..outputDroppedFrames = 0
      ..finishSample();
    expect(metrics.recentDroppedFrames, 0);
    metrics
      ..outputDroppedFrames = 3
      ..finishSample();
    expect(metrics.recentDroppedFrames, 3);
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
