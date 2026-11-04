import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/utils/playback_drop_accounting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = jsonDecode(
    File('test/fixtures/long_press_drop_recovery/input.json')
        .readAsStringSync(),
  ) as List;
  final reference = jsonDecode(
    File('test/fixtures/long_press_drop_recovery/reference.json')
        .readAsStringSync(),
  ) as List;
  for (var index = 0; index < input.length; index++) {
    final sample = input[index] as Map<String, dynamic>;
    test(sample['name'] as String, () {
      final accounting = PlaybackDropAccounting()
        ..firstFrame(0)
        ..sample(0, nowMs: 4000, finishInterval: true);
      final actual = <List<int>>[];
      for (final event in sample['events'] as List) {
        final now = event[1] as int;
        switch (event[0]) {
          case 'release':
            accounting.beginLongPressRecovery();
          case 'end':
            accounting.endLongPressRecovery();
          case 'transition':
            accounting.speedTransition(now, reuseAllowance: true);
          case 'reset':
            accounting
              ..reset()
              ..firstFrame(now);
          case 'sample':
            accounting.sample(
              event[2] as int,
              nowMs: now,
              finishInterval: event.length > 3 && event[3] == true,
            );
          default:
            fail('未知样例事件：${event[0]}');
        }
        actual.add([
          accounting.droppedFrames,
          accounting.recentDroppedFrames,
          accounting.rawDroppedFrames,
          accounting.excludedDroppedFrames,
        ]);
      }
      expect(actual, reference[index]);
    });
  }
}
