import 'package:PiliPlus/plugin/pl_player/utils/playback_drop_accounting.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackDropAccounting stable() => PlaybackDropAccounting()
  ..firstFrame(0)
  ..sample(0, nowMs: 4000, finishInterval: true);

void main() {
  test('首帧前后起播共用五帧，第六帧开始计数', () {
    final c = PlaybackDropAccounting()
      ..sample(2, nowMs: 100)
      ..firstFrame(500)
      ..sample(5, nowMs: 1000, finishInterval: true);
    expect(c.droppedFrames, 0);
    c.sample(7, nowMs: 2000, finishInterval: true);
    expect(c.droppedFrames, 2);
    expect(c.recentDroppedFrames, 2);
    expect(c.excludedDroppedFrames, 5);
  });

  test('进入和退出长按倍速各允许五帧，倍速期间持续计数', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(5, nowMs: 5500, finishInterval: true);
    expect(c.droppedFrames, 0);
    c.sample(9, nowMs: 6000, finishInterval: true);
    expect(c.droppedFrames, 4);
    expect(c.recentDroppedFrames, 4);
    c
      ..sample(11, nowMs: 7500, finishInterval: true)
      ..sample(14, nowMs: 8500, finishInterval: true);
    expect(c.droppedFrames, 9);
    c
      ..speedTransition(9000)
      ..sample(19, nowMs: 9500, finishInterval: true);
    expect(c.droppedFrames, 9);
    c.sample(22, nowMs: 10000, finishInterval: true);
    expect(c.droppedFrames, 12);
    expect(c.recentDroppedFrames, 3);
    expect(c.excludedDroppedFrames, 10);
  });

  test('短按进入和退出的窗口重叠时仍各有五帧', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(5, nowMs: 5100)
      ..speedTransition(5200)
      ..sample(10, nowMs: 5300, finishInterval: true)
      ..sample(11, nowMs: 5500, finishInterval: true);
    expect(c.droppedFrames, 1);
    expect(c.excludedDroppedFrames, 10);
  });

  test('单次切速的五帧额度跨采样累计，不能每秒重新排除', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(3, nowMs: 5500, finishInterval: true)
      ..sample(7, nowMs: 6500, finishInterval: true);
    expect(c.droppedFrames, 2);
    expect(c.excludedDroppedFrames, 5);
  });

  test('大幅丢帧只减去五帧，不再整段屏蔽或等待连续异常', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(60, nowMs: 5500, finishInterval: true);
    expect(c.droppedFrames, 55);
    expect(c.recentDroppedFrames, 55);
    expect(c.excludedDroppedFrames, 5);
  });

  test('稳定播放孤立一帧也正常计入，不被持续性过滤吞掉', () {
    final c = stable()..sample(1, nowMs: 5000, finishInterval: true);
    expect(c.droppedFrames, 1);
    expect(c.recentDroppedFrames, 1);
    c.sample(1, nowMs: 6000, finishInterval: true);
    expect(c.droppedFrames, 1);
    expect(c.recentDroppedFrames, 0);
  });

  test('过渡结束后未用完的额度失效，不抵扣后续稳定丢帧', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(2, nowMs: 5500, finishInterval: true)
      ..sample(2, nowMs: 7500, finishInterval: true)
      ..sample(5, nowMs: 8500, finishInterval: true);
    expect(c.droppedFrames, 3);
    expect(c.excludedDroppedFrames, 2);
  });

  test('跨边界延迟上报也只能排除五帧，不能整次采样丢弃', () {
    final c = stable()
      ..speedTransition(5000)
      ..sample(8, nowMs: 7500, finishInterval: true)
      ..sample(9, nowMs: 8500, finishInterval: true);
    expect(c.droppedFrames, 4);
    expect(c.excludedDroppedFrames, 5);
  });

  test('连续切速不叠加未使用的额度', () {
    final c = stable()
      ..speedTransition(5000)
      ..speedTransition(5100)
      ..speedTransition(5200)
      ..sample(12, nowMs: 5500, finishInterval: true);
    expect(c.droppedFrames, 7);
    expect(c.excludedDroppedFrames, 5);
  });

  for (final buffering in [false, true]) {
    test('暂停或缓冲不计播放丢帧，恢复后不额外屏蔽：$buffering', () {
      final c = stable()
        ..sample(2, nowMs: 5000, finishInterval: true)
        ..sample(
          20,
          nowMs: 6000,
          finishInterval: true,
          isPlaying: buffering,
          isBuffering: buffering,
        );
      expect(c.droppedFrames, 2);
      expect(c.recentDroppedFrames, 0);
      c.sample(21, nowMs: 7000, finishInterval: true);
      expect(c.droppedFrames, 3);
      expect(c.recentDroppedFrames, 1);
      expect(c.rawDroppedFrames, c.droppedFrames + c.excludedDroppedFrames);
    });
  }

  test('后端清零后保留历史总数，不重新发放起播容差', () {
    final c = stable()
      ..sample(15, nowMs: 5000, finishInterval: true)
      ..sample(0, nowMs: 6000, finishInterval: true);
    expect(c.droppedFrames, 15);
    expect(c.recentDroppedFrames, 0);
    c.sample(6, nowMs: 7000, finishInterval: true);
    expect(c.droppedFrames, 21);
    expect(c.rawDroppedFrames, 21);
    expect(c.excludedDroppedFrames, 0);
  });

  test('只有显式新会话重置会清除累计并恢复起播容差', () {
    final c = stable()
      ..sample(15, nowMs: 5000, finishInterval: true)
      ..reset()
      ..firstFrame(8000)
      ..sample(5, nowMs: 9000, finishInterval: true);
    expect(c.droppedFrames, 0);
    expect(c.rawDroppedFrames, 5);
    expect(c.excludedDroppedFrames, 5);
    expect(c.recentDroppedFrames, 0);
  });

  test('预先开启退出容差：后端清零与被排除的帧均不清历史或先计入再扣回', () {
    final c = stable()..sample(12, nowMs: 4500, finishInterval: true);
    final totals = [c.droppedFrames];
    c.speedTransition(5000);
    for (final (total, time) in [(0, 5100), (3, 5200), (5, 5300)]) {
      c.sample(total, nowMs: time, finishInterval: true);
      totals.add(c.droppedFrames);
      expect(c.recentDroppedFrames, 0);
    }
    expect(totals, [12, 12, 12, 12]);
    c.sample(7, nowMs: 5400, finishInterval: true);
    expect(c.droppedFrames, 14);
    expect(c.recentDroppedFrames, 2);
    expect(c.rawDroppedFrames, 19);
    expect(c.excludedDroppedFrames, 5);
  });

  test('松手后exact复用已消耗的额度，不能多排除五帧', () {
    final c = stable()
      ..sample(12, nowMs: 4500, finishInterval: true)
      ..speedTransition(5000)
      ..sample(15, nowMs: 5050, finishInterval: true)
      ..speedTransition(5080, reuseAllowance: true)
      ..sample(0, nowMs: 5100)
      ..sample(4, nowMs: 5500, finishInterval: true);
    expect(c.droppedFrames, 14);
    expect(c.recentDroppedFrames, 2);
    expect(c.excludedDroppedFrames, 5);
    expect(c.rawDroppedFrames, 19);
  });

  test('负数或重复计数不重置基线，也不重复累计历史', () {
    final c = stable()
      ..sample(12, nowMs: 5000, finishInterval: true)
      ..sample(-1, nowMs: 5500)
      ..sample(12, nowMs: 5600)
      ..sample(13, nowMs: 6000, finishInterval: true);
    expect(c.droppedFrames, 13);
    expect(c.recentDroppedFrames, 1);
  });

  test('重复界面快照不重复计数或消耗近期告警，下一秒正常归零', () {
    final c = stable()
      ..sample(3, nowMs: 4500)
      ..sample(3, nowMs: 4600)
      ..sample(4, nowMs: 5000, finishInterval: true);
    expect(c.droppedFrames, 4);
    expect(c.recentDroppedFrames, 4);
    c.sample(4, nowMs: 5100);
    expect(c.recentDroppedFrames, 4);
    c.sample(4, nowMs: 6000, finishInterval: true);
    expect(c.recentDroppedFrames, 0);
    expect(c.droppedFrames, 4);
  });
}
