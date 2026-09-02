import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'piliexo-font-weight-setting-test-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await GStorage.setting.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('旧版默认字重迁移后保持正常字重', () async {
    await GStorage.setting.clear();
    await GStorage.setting.put('appFontWeight', -1);

    expect(Pref.appFontWeight, FontWeight.normal);
    expect(GStorage.setting.get('appFontWeight'), isNull);
  });

  test('旧版字重迁移到新版键并保留字重', () async {
    await GStorage.setting.clear();
    final weightIndex = FontWeight.values.indexOf(FontWeight.w700);
    await GStorage.setting.put('appFontWeight', weightIndex);

    expect(Pref.appFontWeight, FontWeight.w700);
    expect(
      GStorage.setting.get(SettingBoxKey.appFontWeightV2),
      weightIndex,
    );
    expect(GStorage.setting.get('appFontWeight'), isNull);
  });

  test('异常字重索引会限制在有效范围', () async {
    await GStorage.setting.clear();
    await GStorage.setting.put(
      SettingBoxKey.appFontWeightV2,
      FontWeight.values.length + 10,
    );

    expect(Pref.appFontWeight, FontWeight.w900);
  });
}
