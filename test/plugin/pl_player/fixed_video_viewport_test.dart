import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/fixed_video_viewport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
