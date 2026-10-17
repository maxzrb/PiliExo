import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/playback_rate_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('等待播放器操作锁时松手，不再向后端发送旧加速', () async {
    final lock = Completer<void>();
    final sent = <double>[];
    final confirmed = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (rate, isCurrent) async {
        await lock.future;
        if (isCurrent()) sent.add(rate);
      },
      onConfirmed: confirmed.add,
    );
    final hold = rates.beginTemporary(3);
    final release = rates.endTemporary();
    lock.complete();
    await Future.wait([hold, release]);
    expect(sent, [1]);
    expect(confirmed, [1]);
  });

  test('等待操作锁期间连续改变目标，仅发送最终基础倍速', () async {
    final lock = Completer<void>();
    final sent = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1.5,
      apply: (rate, isCurrent) async {
        await lock.future;
        if (isCurrent()) sent.add(rate);
      },
      onConfirmed: (_) {},
    );
    final first = rates.beginTemporary(3);
    rates
      ..endTemporary()
      ..beginTemporary(4);
    final last = rates.endTemporary();
    lock.complete();
    await Future.wait([first, last]);
    expect(sent, [1.5]);
    expect(rates.confirmedRate, 1.5);
  });

  test('切源或释放使等待中的旧请求在后端执行前失效', () async {
    for (final dispose in [false, true]) {
      final lock = Completer<void>();
      final sent = <double>[];
      final rates = PlaybackRateCoordinator(
        initialRate: 1,
        apply: (rate, isCurrent) async {
          await lock.future;
          if (isCurrent()) sent.add(rate);
        },
        onConfirmed: (_) {},
      );
      final old = rates.beginTemporary(3);
      if (dispose) {
        rates.dispose();
      } else {
        rates.resetForSource();
      }
      lock.complete();
      await old;
      expect(sent, isEmpty);
    }
  });

  test('松手丢弃尚未执行的旧目标，迟到结果不更新界面', () async {
    final gate = Completer<void>();
    final sent = <double>[];
    final confirmed = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (rate, _) async {
        sent.add(rate);
        if (sent.length == 1) await gate.future;
      },
      onConfirmed: confirmed.add,
    );
    final first = rates.beginTemporary(3);
    final second = rates.endTemporary();
    final third = rates.beginTemporary(3);
    final last = rates.endTemporary();
    gate.complete();
    await Future.wait([first, second, third, last]);
    expect(sent, [3, 1]);
    expect(confirmed, [1]);
    expect(rates.baseRate, 1);
    expect(rates.confirmedRate, 1);
    expect(rates.isTemporary, isFalse);
  });

  test('基础1.5倍速连续长按后仍恢复1.5', () async {
    final sent = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1.5,
      apply: (rate, _) async => sent.add(rate),
      onConfirmed: (_) {},
    );
    await rates.beginTemporary(3);
    await rates.endTemporary();
    await rates.beginTemporary(4);
    await rates.endTemporary();
    expect(sent, [3, 1.5, 4, 1.5]);
    expect(rates.baseRate, 1.5);
  });

  test('手动选择倍速结束临时加速并更新恢复目标', () async {
    final sent = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (rate, _) async => sent.add(rate),
      onConfirmed: (_) {},
    );
    await rates.beginTemporary(3);
    await rates.setBaseRate(2);
    await rates.endTemporary();
    expect(sent, [3, 2]);
    expect(rates.baseRate, 2);
    expect(rates.isTemporary, isFalse);
  });

  test('旧加速命令失败不会阻止松手恢复', () async {
    final gate = Completer<void>();
    final confirmed = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (rate, _) async {
        if (rate == 3) {
          await gate.future;
          throw StateError('模拟旧请求失败');
        }
      },
      onConfirmed: confirmed.add,
    );
    final first = rates.beginTemporary(3);
    final release = rates.endTemporary();
    gate.complete();
    await Future.wait([first, release]);
    expect(confirmed, [1]);
  });

  test('最终命令失败后可以重试且不会误报确认速度', () async {
    var fail = true;
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (_, _) async {
        if (fail) throw StateError('模拟最终请求失败');
      },
      onConfirmed: (_) {},
    );
    await expectLater(rates.setBaseRate(2), throwsStateError);
    expect(rates.confirmedRate, isNull);
    fail = false;
    await rates.setBaseRate(2);
    expect(rates.confirmedRate, 2);
  });

  test('切源废弃旧确认并重新向新源发送基础速度', () async {
    final gate = Completer<void>();
    final sent = <double>[];
    final confirmed = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1.5,
      apply: (rate, _) async {
        sent.add(rate);
        if (sent.length == 1) await gate.future;
      },
      onConfirmed: confirmed.add,
    );
    final first = rates.beginTemporary(3);
    rates.resetForSource();
    final next = rates.setBaseRate(rates.baseRate);
    await next;
    expect(confirmed, [1.5]);
    gate.complete();
    await Future.wait([first, next]);
    expect(sent, [3, 1.5]);
    expect(confirmed, [1.5]);
  });

  test('释放后迟到结果不再通知页面', () async {
    final gate = Completer<void>();
    final confirmed = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (_, _) => gate.future,
      onConfirmed: confirmed.add,
    );
    final first = rates.beginTemporary(3);
    rates.dispose();
    gate.complete();
    await first;
    expect(confirmed, isEmpty);
    expect(() => rates.setBaseRate(1), throwsStateError);
  });

  test('拒绝无效速度，不污染基础速度', () {
    final rates = PlaybackRateCoordinator(
      initialRate: 1,
      apply: (_, _) async {},
      onConfirmed: (_) {},
    );
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => rates.setBaseRate(value), throwsArgumentError);
    }
    expect(rates.baseRate, 1);
  });
}
