import 'dart:io';

import 'package:PiliPlus/pages/setting/pages/play_speed_set.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-speed-setting-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.video = await Hive.openBox('video');
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.video.clear();
  });
  tearDownAll(() async {
    await GStorage.video.close();
    await GStorage.localCache.close();
    await GStorage.setting.close();
    await directory.delete(recursive: true);
  });

  test('未配置时长按为2倍、直接同步；保留用户已有倍率与同步设置', () async {
    expect(Pref.longPressSpeedDefault, 2);
    expect(Pref.autosync, '0');
    await GStorage.video.put(VideoBoxKey.longPressSpeedDefault, 2.5);
    await GStorage.setting.put(SettingBoxKey.autosync, '15');
    expect(Pref.longPressSpeedDefault, 2.5);
    expect(Pref.autosync, '15');
  });

  test('已有播放器下一次长按读取新保存的倍率', () async {
    final controller = PlPlayerController.getInstance();
    expect(controller.longPressTargetSpeed, 2);
    await GStorage.video.put(VideoBoxKey.longPressSpeedDefault, 1.75);
    expect(Pref.longPressSpeedDefault, 1.75);
    expect(controller.longPressTargetSpeed, 1.75);
    controller.playerStatus.value = .paused;
    controller.dispose();
  });

  testWidgets('无效倍率不保存，取消编辑保留已有值', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlaySpeedPage()));
    await tester.tap(find.text('长按倍速'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('请输入大于 0 的有效倍速'), findsOneWidget);
    expect(Pref.longPressSpeedDefault, 2);
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(Pref.longPressSpeedDefault, 2);
  });
}
