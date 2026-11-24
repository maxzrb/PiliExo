import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/first_frame_cover.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/fixed_video_viewport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('起播时保留黑底，纹理提交首帧后移除遮挡', (tester) async {
    final firstFrame = Completer<void>();
    const video = ValueKey('video');
    const black = Color(0xFF000000);
    final cover = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == black,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FirstFrameCover(
          firstFrame: firstFrame.future,
          color: black,
          child: const SizedBox(width: 320, height: 180, key: video),
        ),
      ),
    );
    final videoElement = tester.element(find.byKey(video));
    expect(cover, findsOneWidget);
    expect(tester.getSize(cover), tester.getSize(find.byKey(video)));

    firstFrame.complete();
    await tester.pumpAndSettle();

    expect(cover, findsNothing);
    expect(tester.element(find.byKey(video)), same(videoElement));
  });

  testWidgets('固定滚动输入：评论区返回顶部时视频尺寸和元素保持稳定', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const viewportKey = ValueKey('viewport');
    const videoKey = ValueKey('video');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            VideoHeader(
              minExtent: 56,
              maxExtent: 225,
              minVideoHeight: 225,
              onScrollRatioChanged: (_) {},
              child: const FixedVideoViewport(
                key: viewportKey,
                width: 400,
                height: 225,
                child: SizedBox.expand(key: videoKey),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 3000)),
          ],
        ),
      ),
    );
    final element = tester.element(find.byKey(videoKey));
    final cases = jsonDecode(
      File('test/fixtures/mpv_hdr/viewport-scroll.json')
          .readAsStringSync(encoding: utf8),
    ) as List;
    String dimensions(Size size) =>
        '${size.width.toInt()}x${size.height.toInt()}';
    final actual = <String>[];
    for (final sample in cases.cast<Map<String, dynamic>>()) {
      scroll.jumpTo((sample['offset'] as num).toDouble());
      await tester.pump();
      final visible = tester.getSize(find.byKey(viewportKey));
      final video = tester.getSize(find.byKey(videoKey));
      final retained = identical(element, tester.element(find.byKey(videoKey)));
      actual.add(
        '${sample['id']} visible=${dimensions(visible)} video=${dimensions(video)} retained=$retained',
      );
    }
    expect(
      '${actual.join('\n')}\n',
      File('test/ref/fate/mpv-hdr-viewport-scroll')
          .readAsStringSync(encoding: utf8),
    );
  });

  testWidgets('路线折叠输入：mpv 兼容缩小画面，原生 HDR 固定视频层', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final groups = jsonDecode(
      File('test/fixtures/mpv_hdr/viewport-routes.json')
          .readAsStringSync(encoding: utf8),
    ) as List;
    String dimensions(Size size) =>
        '${size.width.toInt()}x${size.height.toInt()}';
    final actual = <String>[];
    for (final sample in groups.cast<Map<String, dynamic>>()) {
      final id = sample['id'] as String;
      final viewportKey = ValueKey('viewport-$id');
      final videoKey = ValueKey('video-$id');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              VideoHeader(
                minExtent: 56,
                maxExtent: 225,
                minVideoHeight: 225,
                onScrollRatioChanged: (_) {},
                child: CollapsingVideoViewport(
                  key: viewportKey,
                  animateShrink: sample['animateShrink'] as bool,
                  width: 400,
                  height: 225,
                  child: SizedBox.expand(key: videoKey),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 3000)),
            ],
          ),
        ),
      );
      final element = tester.element(find.byKey(videoKey));
      for (final offset in sample['offsets'] as List) {
        final value = (offset as num).toInt();
        scroll.jumpTo(value.toDouble());
        await tester.pump();
        final visible = tester.getSize(find.byKey(viewportKey));
        final video = tester.getSize(find.byKey(videoKey));
        final retained = identical(
          element,
          tester.element(find.byKey(videoKey)),
        );
        actual.add(
          '$id offset=$value visible=${dimensions(visible)} '
          'video=${dimensions(video)} retained=$retained',
        );
      }
    }
    expect(
      '${actual.join('\n')}\n',
      File('test/ref/fate/mpv-hdr-viewport-routes')
          .readAsStringSync(encoding: utf8),
    );
  });

  testWidgets('全屏固定视频头：页面残留滚动偏移不会缩短播放器', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const viewportKey = ValueKey('fullscreen-viewport');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            VideoHeader(
              minExtent: 800,
              maxExtent: 800,
              minVideoHeight: 800,
              onScrollRatioChanged: (_) {},
              child: const FixedVideoViewport(
                key: viewportKey,
                width: 400,
                height: 800,
                child: SizedBox.expand(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 3000)),
          ],
        ),
      ),
    );
    for (final offset in [0, 1, 100, 600]) {
      scroll.jumpTo(offset.toDouble());
      await tester.pump();
      expect(
        tester.getSize(find.byKey(viewportKey)),
        const Size(400, 800),
        reason: 'scrollOffset=$offset',
      );
      expect(
        tester.getTopLeft(find.byKey(viewportKey)),
        Offset.zero,
        reason: 'scrollOffset=$offset',
      );
    }
  });
}
