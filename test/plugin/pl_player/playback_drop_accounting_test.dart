import 'package:PiliPlus/plugin/pl_player/utils/playback_drop_accounting.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackDropAccounting stable() => PlaybackDropAccounting()
  ..firstFrame(0)
  ..sample(0, nowMs: 4000, finishInterval: true);

void main() {
  test('起播三帧和延迟上报的过渡计数不触发异常', () {
    final c = PlaybackDropAccounting()
      ..sample(1, nowMs: 100)
      ..firstFrame(500)
      ..sample(3, nowMs: 1000, finishInterval: true)
      ..sample(4, nowMs: 4000, finishInterval: true);
    expect(c.droppedFrames, 0);
    expect(c.rawDroppedFrames, 4);
    expect(c.excludedDroppedFrames, 4);
  });
  test('切速结束的短暂重对齐不因超过两帧而突然全部报回', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(3, nowMs: 6000, finishInterval: true)
      ..sample(8, nowMs: 7500, finishInterval: true)
      ..sample(8, nowMs: 8500, finishInterval: true);
    expect(c.droppedFrames, 0);
    expect(c.rawDroppedFrames, 8);
  });
  test('稳定区间孤立三帧不会弹出提示，下一正常区间清除候选', () {
    final c = stable()..sample(3, nowMs: 5000, finishInterval: true);
    expect(c.droppedFrames, 0);
    c.sample(3, nowMs: 6000, finishInterval: true);
    expect(c.droppedFrames, 0);
    expect(c.excludedDroppedFrames, 3);
  });
  test('稳定播放连续掉帧会补记首次证据并通知', () {
    final c = stable()
      ..sample(3, nowMs: 5000, finishInterval: true)
      ..sample(7, nowMs: 6000, finishInterval: true);
    expect(c.droppedFrames, 7);
    expect(c.recentDroppedFrames, 7);
    c.sample(8, nowMs: 7000, finishInterval: true);
    expect(c.droppedFrames, 8);
    expect(c.recentDroppedFrames, 1);
  });
  test('严重突发立即报告，不等待第二个区间', () {
    final c = stable()..sample(15, nowMs: 5000, finishInterval: true);
    expect(c.droppedFrames, 15);
    expect(c.recentDroppedFrames, 15);
  });
  test('恢复后继续掉帧仍可被捕获，过渡历史不倒灌', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(20, nowMs: 6000, finishInterval: true)
      ..sample(22, nowMs: 7500, finishInterval: true)
      ..sample(25, nowMs: 8500, finishInterval: true)
      ..sample(28, nowMs: 9500, finishInterval: true);
    expect(c.droppedFrames, 6);
    expect(c.excludedDroppedFrames, 22);
  });
  test('连续长按不能无限延长屏蔽窗口', () {
    final c = stable()..speedTransition(5000);
    for (final time in [6500, 8000, 9500, 11000]) {
      c.speedTransition(time);
    }
    c
      ..sample(3, nowMs: 11001, finishInterval: true)
      ..speedTransition(11500)
      ..sample(4, nowMs: 12000, finishInterval: true)
      ..speedTransition(12500)
      ..sample(5, nowMs: 13000, finishInterval: true);
    expect(c.droppedFrames, 2);
  });
  test('新过渡清除孤立候选，不与过渡后无关计数组合报警', () {
    final c = stable()
      ..sample(3, nowMs: 5000, finishInterval: true)
      ..speedTransition(5500)
      ..sample(6, nowMs: 8000, finishInterval: true)
      ..sample(7, nowMs: 9000, finishInterval: true)
      ..sample(7, nowMs: 10000, finishInterval: true);
    expect(c.droppedFrames, 0);
  });
  for (final buffering in [false, true]) {
    test('暂停或网络缓冲清除未确认计数，不伪报设备性能不足：$buffering', () {
      final c = stable()
        ..sample(3, nowMs: 5000, finishInterval: true)
        ..sample(
          20,
          nowMs: 6000,
          finishInterval: true,
          isPlaying: buffering,
          isBuffering: buffering,
        )
        ..sample(21, nowMs: 7000, finishInterval: true)
        ..sample(22, nowMs: 8000, finishInterval: true)
        ..sample(22, nowMs: 9000, finishInterval: true);
      expect(c.droppedFrames, 0);
      expect(c.rawDroppedFrames, 22);
    });
  }
  test('计数回退不会产生负数或继承旧异常', () {
    final c = stable()
      ..sample(15, nowMs: 5000, finishInterval: true)
      ..sample(0, nowMs: 6000, finishInterval: true)
      ..sample(1, nowMs: 7000, finishInterval: true);
    expect(c.droppedFrames, 0);
    expect(c.excludedDroppedFrames, 1);
    c
      ..reset()
      ..sample(3, nowMs: 9000, finishInterval: true);
    expect(c.droppedFrames, 0);
    expect(c.rawDroppedFrames, 3);
  });
  test('普通快照刷新不伪造连续区间，也不消耗告警', () {
    final c = stable()
      ..sample(3, nowMs: 4500)
      ..sample(3, nowMs: 4600)
      ..sample(3, nowMs: 5000, finishInterval: true);
    expect(c.droppedFrames, 0);
    c.sample(4, nowMs: 6000, finishInterval: true);
    expect(c.recentDroppedFrames, 4);
    c.sample(4, nowMs: 6100);
    expect(c.recentDroppedFrames, 4);
    c.sample(4, nowMs: 7000, finishInterval: true);
    expect(c.recentDroppedFrames, 0);
    expect(c.rawDroppedFrames, c.droppedFrames + c.excludedDroppedFrames);
  });
}
