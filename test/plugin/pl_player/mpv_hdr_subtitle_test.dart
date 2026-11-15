import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/widgets/mpv_hdr_subtitle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  testWidgets('字幕双行、弹幕与控制按钮可以同时显示和响应', (tester) async {
    final cues = StreamController<Subtitle>.broadcast();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                IgnorePointer(
                  child: MpvHdrSubtitle(
                    subtitleStream: cues.stream,
                    initialSubtitle: const Subtitle.raw(
                      'HDR 字幕样例',
                      'Second subtitle line',
                    ),
                    configuration: const SubtitleViewConfiguration(
                      style: TextStyle(fontSize: 16),
                    ),
                    enableDrag: false,
                    onUpdatePadding: (_) {},
                  ),
                ),
                const Positioned(top: 20, child: Text('滚动弹幕样例')),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('暂停'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('HDR 字幕样例\nSecond subtitle line'), findsOneWidget);
    expect(find.text('滚动弹幕样例'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    expect(taps, 1);

    cues.add(const Subtitle.raw('切换后的字幕'));
    await tester.pump();
    expect(find.text('切换后的字幕'), findsOneWidget);
    expect(find.text('HDR 字幕样例\nSecond subtitle line'), findsNothing);
    cues.add(const Subtitle.raw());
    await tester.pump();
    expect(find.text('切换后的字幕'), findsNothing);
    expect(find.text('滚动弹幕样例'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(cues.hasListener, isFalse);
    await cues.close();
  });

  testWidgets('原生输出字幕支持拖动位置和隐藏设置', (tester) async {
    final cues = StreamController<Subtitle>.broadcast();
    EdgeInsets? savedPadding;
    Widget sample({bool visible = true}) => MaterialApp(
      home: SizedBox(
        width: 400,
        height: 240,
        child: MpvHdrSubtitle(
          subtitleStream: cues.stream,
          initialSubtitle: const Subtitle.raw('拖动字幕'),
          configuration: SubtitleViewConfiguration(
            visible: visible,
            style: const TextStyle(fontSize: 16),
          ),
          enableDrag: true,
          onUpdatePadding: (value) => savedPadding = value,
        ),
      ),
    );
    await tester.pumpWidget(sample());
    await tester.drag(find.text('拖动字幕'), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(savedPadding, isNotNull);
    expect(savedPadding!.bottom, greaterThan(24));
    expect(savedPadding!.bottom, lessThanOrEqualTo(200));
    await tester.pumpWidget(sample(visible: false));
    expect(find.text('拖动字幕'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await cues.close();
  });
}
