import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fixture = 'test/fixtures/fullscreen_viewport';
  final input = jsonDecode(
    File('$fixture/input.json').readAsStringSync(),
  ) as List<dynamic>;
  final reference = jsonDecode(
    File('$fixture/reference.json').readAsStringSync(),
  );
  testWidgets('FATE 全屏等待实际视口尺寸', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    final output = <String, Map<String, List<bool>>>{};
    for (final row in input) {
      final value = row as Map<String, dynamic>;
      final initial = (value['initial'] as List<dynamic>).cast<num>();
      tester.view.physicalSize = Size(
        initial[0].toDouble(),
        initial[1].toDouble(),
      );
      var ready = false;
      final future = waitForFullscreenViewport(
        value['landscape'] as bool,
      ).then((_) => ready = true);
      await tester.pump();
      bool fullscreenLayout() => useFullscreenViewportLayout(
        viewport: tester.view.physicalSize,
        fullscreen: false,
        targetLandscape: value['landscape'] as bool,
      );
      final result = <bool>[ready];
      final layouts = <bool>[fullscreenLayout()];
      for (final step in value['steps'] as List<dynamic>) {
        final metrics = (step as List<dynamic>).cast<num>();
        tester.view.physicalSize = Size(
          metrics[1].toDouble(),
          metrics[2].toDouble(),
        );
        await tester.pump(Duration(milliseconds: metrics[0].toInt()));
        result.add(ready);
        layouts.add(fullscreenLayout());
      }
      output[value['name'] as String] = {
        'ready': result,
        'fullscreenTransitionLayout': layouts,
      };
      unawaited(future);
    }
    expect(output, reference);
  });
}
