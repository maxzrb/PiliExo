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
    expect(metrics.droppedFrames, 103);
  });

  test('输出和解码计数分别清零时增量独立累计，不相互抵消', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 100
      ..decoderDroppedFrames = 10
      ..finishSample();
    metrics
      ..outputDroppedFrames = 0
      ..decoderDroppedFrames = 13
      ..finishSample();
    expect(metrics.droppedFrames, 113);
    expect(metrics.recentDroppedFrames, 3);
    metrics
      ..outputDroppedFrames = 2
      ..decoderDroppedFrames = 0
      ..finishSample();
    expect(metrics.droppedFrames, 115);
    expect(metrics.recentDroppedFrames, 2);
    metrics
      ..decoderDroppedFrames = 4
      ..finishSample();
    expect(metrics.droppedFrames, 119);
    expect(metrics.recentDroppedFrames, 4);
  });

  test('属性暂时未知或无效时不清基线，恢复后只计算新增值', () {
    final metrics = MpvRuntimeMetrics()
      ..outputDroppedFrames = 100
      ..finishSample();
    metrics
      ..outputDroppedFrames = null
      ..finishSample();
    expect(metrics.droppedFrames, 100);
    metrics
      ..outputDroppedFrames = -1
      ..finishSample();
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
