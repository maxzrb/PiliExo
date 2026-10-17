import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/frosted_surface.dart';
import 'package:PiliPlus/models/common/frosted_surface_style.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-frosted-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await GStorage.setting.deleteFromDisk();
    await directory.delete();
  });

  Widget scene(GlobalKey key, Brightness brightness, {bool uniform = true}) =>
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff52648b),
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 300,
                child: ColoredBox(
                  color: const Color(0xff183245),
                  child: Center(
                    child: SizedBox(
                      width: 180,
                      height: 60,
                      child: FrostedSurface(
                        backgroundIsUniform: uniform,
                        showBorder: true,
                        borderRadius: BorderRadius.circular(14),
                        child: const Center(child: Text('磨砂顶栏')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<Uint8List> pixels(WidgetTester tester, GlobalKey key) async =>
      (await tester.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }))!;

  testWidgets('纯色背景优化在亮暗主题和三档磨砂下仅有圆角边缘的少量混合差异', (tester) async {
    final key = GlobalKey();
    for (final brightness in Brightness.values) {
      for (final style in FrostedSurfaceStyle.values) {
        FrostedSurfaceConfig.update(
          enabled: true,
          style: style,
          optimizeUniformBackground: false,
        );
        await tester.pumpWidget(scene(key, brightness));
        await tester.pumpAndSettle();
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          isTrue,
        );
        final before = await pixels(tester, key);
        final interior = tester
            .getRect(find.byType(FrostedSurface))
            .shift(-tester.getTopLeft(find.byKey(key)))
            .deflate(15);
        FrostedSurfaceConfig.update(optimizeUniformBackground: true);
        await tester.pump();
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          isFalse,
        );
        final after = await pixels(tester, key);
        expect(after.length, before.length);
        var maxDifference = 0;
        var totalDifference = 0;
        var changedChannels = 0;
        var interiorMax = 0;
        for (var index = 0; index < before.length; index++) {
          final difference = (before[index] - after[index]).abs();
          final pixel = index ~/ 4;
          if (interior.contains(
                Offset((pixel % 400).toDouble(), (pixel ~/ 400).toDouble()),
              ) &&
              difference > interiorMax) {
            interiorMax = difference;
          }
          totalDifference += difference;
          if (difference > 0) changedChannels++;
          if (difference > maxDifference) maxDifference = difference;
        }
        debugPrint(
          '$brightness/$style: max=$maxDifference mean=${totalDifference / before.length} changed=$changedChannels/${before.length} interiorMax=$interiorMax',
        );
        // 差异仅位于圆角抗锯齿边缘，材质内部和文字必须保持像素一致。
        expect(interiorMax, 0);

        expect(changedChannels / before.length, lessThan(0.001));
        expect(totalDifference / before.length, lessThan(0.001));
        expect(
          maxDifference,
          lessThanOrEqualTo(5),
          reason: '$brightness/$style',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('未声明纯色的动态背景仍使用原有模糊', (tester) async {
    FrostedSurfaceConfig.update(enabled: true, optimizeUniformBackground: true);
    await tester.pumpWidget(
      scene(GlobalKey(), Brightness.light, uniform: false),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关闭磨砂仍保留原来的不透明材质分支', (tester) async {
    FrostedSurfaceConfig.update(
      enabled: false,
      optimizeUniformBackground: true,
    );
    await tester.pumpWidget(scene(GlobalKey(), Brightness.light));
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
