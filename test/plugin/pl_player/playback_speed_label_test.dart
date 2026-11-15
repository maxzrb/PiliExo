import 'dart:io';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PlPlayerController controller;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-speed-label-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.video = await Hive.openBox('video');
    controller = PlPlayerController.getInstance();
  });
  tearDownAll(() async {
    controller.playerStatus.value = .paused;
    controller.dispose();
    await GStorage.video.close();
    await GStorage.localCache.close();
    await GStorage.setting.close();
    await directory.delete(recursive: true);
  });
  testWidgets('倍速提示有可观察依赖，按下和松手不会触发GetX错误', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Obx(() => Text(
      '${controller.longPressTargetSpeed}倍速中',
    ))));
    expect(tester.takeException(), isNull);
    expect(find.text('2.0倍速中'), findsOneWidget);
    controller.longPressStatus.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('2.0倍速中'), findsOneWidget);
    controller.longPressStatus.value = false;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

}
