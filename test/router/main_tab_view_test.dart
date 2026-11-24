import 'dart:async';

import 'package:PiliPlus/pages/main/widgets/main_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('跨页直达目标，快速反向切换保留页面状态和位置', (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    final firstKey = GlobalKey();
    final lastKey = GlobalKey();
    final middleKey = GlobalKey();
    final navigator = GlobalKey<NavigatorState>();
    final settled = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, index, _) => MainTabView(
            index: index,
            axis: Axis.horizontal,
            onSettled: settled.add,
            children: [
              Hero(
                tag: 'video',
                child: SizedBox(key: firstKey),
              ),
              SizedBox(key: middleKey),
              Hero(
                tag: 'video',
                child: SizedBox(key: lastKey),
              ),
            ],
          ),
        ),
      ),
    );
    final firstElement = firstKey.currentContext;
    expect(lastKey.currentContext, isNull);

    selected.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(middleKey.currentContext, isNull);
    final lastElement = lastKey.currentContext;
    expect(TickerMode.valuesOf(firstKey.currentContext!).enabled, isTrue);
    expect(TickerMode.valuesOf(lastElement!).enabled, isTrue);
    expect(settled, isEmpty);
    final firstPosition = tester.getTopLeft(find.byKey(firstKey));
    final lastPosition = tester.getTopLeft(find.byKey(lastKey));
    expect(firstPosition.dx, lessThan(0));
    expect(lastPosition.dx, greaterThan(0));

    selected.value = 0;
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(firstKey)), firstPosition);
    expect(tester.getTopLeft(find.byKey(lastKey)), lastPosition);
    expect(TickerMode.valuesOf(firstKey.currentContext!).enabled, isTrue);
    expect(TickerMode.valuesOf(lastElement).enabled, isTrue);
    await tester.pump(const Duration(milliseconds: 180));
    expect(settled, isEmpty);
    expect(TickerMode.valuesOf(firstKey.currentContext!).enabled, isTrue);
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getTopLeft(find.byKey(firstKey)).dx.abs(), lessThan(2));

    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.getTopLeft(find.byKey(firstKey)), Offset.zero);
    expect(find.byKey(lastKey), findsOneWidget);
    expect(settled, isEmpty);
    await tester.pumpAndSettle();

    expect(settled, [0]);
    expect(TickerMode.valuesOf(firstKey.currentContext!).enabled, isTrue);
    expect(TickerMode.valuesOf(lastElement).enabled, isFalse);
    expect(tester.getTopLeft(find.byKey(firstKey)), Offset.zero);
    expect(firstKey.currentContext, same(firstElement));
    expect(lastKey.currentContext, same(lastElement));
    expect(find.byKey(lastKey), findsNothing);

    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Center(
            child: Hero(tag: 'video', child: SizedBox(width: 100, height: 100)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
