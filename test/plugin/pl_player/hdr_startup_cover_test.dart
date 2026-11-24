import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/backends/media3_hdr.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/hdr_startup_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Media3 extends HdrMedia3Controller {
  final frames = StreamController<HdrMedia3Event>.broadcast();

  @override
  Stream<HdrMedia3Event> get events => frames.stream;

  void renderFrame() => frames.add(
    HdrMedia3Event(sessionId: sessionId, type: 'firstFrame'),
  );
}

void main() {
  testWidgets('原生视图等入场完成后挂载，封面等首帧后撤下', (tester) async {
    final media3 = _Media3();
    addTearDown(media3.frames.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox.expand()),
    );
    unawaited(
      navigator.currentState!.push<void>(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => HdrStartupCover(
            media3: media3,
            cover: const Text('封面'),
            child: const Text('原生视图'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('封面'), findsOneWidget);
    expect(find.text('原生视图'), findsNothing);
    media3.renderFrame();
    await tester.pump();
    expect(find.text('封面'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('原生视图'), findsOneWidget);
    expect(find.text('封面'), findsOneWidget);
    media3.renderFrame();
    await tester.pumpAndSettle();
    expect(find.text('封面'), findsNothing);
    expect(find.text('原生视图'), findsOneWidget);
  });
}
