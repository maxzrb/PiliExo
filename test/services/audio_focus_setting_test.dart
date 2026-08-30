import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'piliexo-audio-focus-setting-test-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await GStorage.setting.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('音频焦点接管默认开启且可持久化关闭', () async {
    await GStorage.setting.delete(SettingBoxKey.enableAudioFocus);
    expect(Pref.enableAudioFocus, isTrue);

    await GStorage.setting.put(SettingBoxKey.enableAudioFocus, false);
    expect(Pref.enableAudioFocus, isFalse);

    await GStorage.setting.put(SettingBoxKey.enableAudioFocus, true);
  });
}
