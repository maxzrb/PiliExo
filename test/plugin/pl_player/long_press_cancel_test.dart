import 'dart:async';

import 'package:PiliPlus/common/widgets/gesture/mouse_interactive_viewer.dart';
import 'package:PiliPlus/plugin/pl_player/utils/playback_rate_coordinator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('已识别长按收到系统取消时仍恢复基础倍速', (tester) async {
    final sent = <double>[];
    final rates = PlaybackRateCoordinator(
      initialRate: 1.5,
      apply: (rate, isCurrent) async {
        if (isCurrent()) sent.add(rate);
      },
      onConfirmed: (_) {},
    );
    final longPress =
        LongPressGestureRecognizer(
            duration: const Duration(milliseconds: 300),
          )
          ..onLongPressStart = (_) {
            unawaited(rates.beginTemporary(3));
          }
          ..onLongPressEnd = (_) {
            unawaited(rates.endTemporary());
          };
    final scale = ScaleGestureRecognizer();
    final transform = TransformationController();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: MouseInteractiveViewer(
              childKey: key,
              pointerSignalFallback: (_) {},
              onPointerDown: longPress.addPointer,
              onPointerCancel: (_) => unawaited(rates.endTemporary()),
              onPanEnd: (_) {},
              onPanStart: (_) {},
              onPanUpdate: (_) {},
              onScaleUpdate: (_) {},
              transformationController: transform,
              scaleGestureRecognizer: scale,
              child: ColoredBox(key: key, color: Colors.black),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MouseInteractiveViewer)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(sent, [3]);
    await gesture.cancel();
    await tester.pump();
    expect(sent, [3, 1.5]);
    expect(rates.isTemporary, isFalse);
    await tester.pumpWidget(const SizedBox());
    longPress.dispose();
    scale.dispose();
    transform.dispose();
    rates.dispose();
  });
}
