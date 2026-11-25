import 'dart:io';

import 'package:PiliPlus/utils/downloadable_font.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
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
    appSupportDirPath = hiveDirectory.path;
    await GStorage.setting.put(SettingBoxKey.appFont, '');
  });

  test('删除已下载字体时只重置正在使用的字族', () async {
    final previous = FontUtils.appFont;
    addTearDown(() => FontUtils.appFont = previous);
    const active = DownloadableFont.harmonyOs;
    const inactive = DownloadableFont.miSans;
    await Directory('$appSupportDirPath/harmonyos-sans-2.400').create();
    await Directory('$appSupportDirPath/misans-vf').create();
    FontUtils.appFont = (fontFamily: active.family, isCustom: false);
    await GStorage.setting.put(SettingBoxKey.appFont, active.family);

    expect(await FontUtils.removeDownloadedFont(inactive), isFalse);
    expect(inactive.isInstalled, isFalse);
    expect(active.isInstalled, isTrue);
    expect(FontUtils.fontFamily, active.family);
    expect(GStorage.setting.get(SettingBoxKey.appFont), active.family);

    expect(await FontUtils.removeDownloadedFont(active), isTrue);
    expect(active.isInstalled, isFalse);
    expect(FontUtils.fontFamily, isNull);
    expect(GStorage.setting.get(SettingBoxKey.appFont), isNull);
  });

  tearDownAll(() async {
    await GStorage.setting.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('默认使用系统字体，兼容旧版保存的空字符串', () {
    final previous = FontUtils.appFont;
    addTearDown(() => FontUtils.appFont = previous);
    expect(previous, (fontFamily: null, isCustom: false));
    expect(FontUtils.fontFamily, isNull);
    FontUtils.appFont = (
      fontFamily: 'Noto Sans CJK SC',
      isCustom: false,
    );
    expect(FontUtils.fontFamily, 'Noto Sans CJK SC');
  });

  test('升级时清理文楷缓存并恢复系统字体', () async {
    final previous = FontUtils.appFont;
    addTearDown(() => FontUtils.appFont = previous);
    final retired = await Directory(
      '$appSupportDirPath/lxgw-wenkai-lite-1.530',
    ).create();
    final retained = await Directory('$appSupportDirPath/misans-vf').create();
    await File('${retired.path}/Regular.ttf').writeAsBytes([1]);
    const previousFamily = 'LXGW WenKai Lite';
    FontUtils.appFont = (fontFamily: previousFamily, isCustom: false);
    await GStorage.setting.put(SettingBoxKey.appFont, previousFamily);

    await FontUtils.init();

    expect(retired.existsSync(), isFalse);
    expect(retained.existsSync(), isTrue);
    expect(FontUtils.fontFamily, isNull);
    expect(GStorage.setting.get(SettingBoxKey.appFont), isNull);
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
