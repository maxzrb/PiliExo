import 'package:PiliPlus/utils/default_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认设置排除账号标识、WebDAV 和设备派生值', () {
    final defaults = createDefaultSettingValues();

    for (final key in [
      'buvid',
      'webdavDirectory',
      'webdavPassword',
      'webdavUri',
      'webdavUsername',
      'displayMode',
      'fullScreenSCWidth',
    ]) {
      expect(defaults, isNot(contains(key)));
    }
  });

  test('HDR 默认路线为 mpv 原生', () {
    final defaults = createDefaultSettingValues();

    expect(defaults['hdrPlaybackRoute'], 'mpv-native');
    expect(defaults['enableMpvHdr'], isTrue);
    expect(defaults['enableMedia3Hdr'], isFalse);
  });

  test('只补充缺失值，不覆盖已有设置', () {
    final settings = <dynamic, dynamic>{
      'themeMode': 0,
      'danmakuBlockType': <int>[42],
    };

    final added = applyMissingDefaultValues(
      createDefaultSettingValues(),
      containsKey: settings.containsKey,
      setValue: (key, value) => settings[key] = value,
    );

    expect(settings['themeMode'], 0);
    expect(settings['danmakuBlockType'], <int>[42]);
    expect(settings['defaultVideoQa'], 129);
    expect(settings['msgUnReadTypeV2'], <int>[0, 1, 2, 4]);
    expect(added, createDefaultSettingValues().length - 2);
  });

  test('列表默认值每次创建独立实例', () {
    final first = createDefaultSettingValues();
    final second = createDefaultSettingValues();

    (first['danmakuBlockType'] as List<int>).add(7);

    expect(second['danmakuBlockType'], isEmpty);
  });

  test('视频默认设置单独迁移', () {
    final video = <dynamic, dynamic>{};

    expect(
      applyMissingDefaultValues(
        createDefaultVideoValues(),
        containsKey: video.containsKey,
        setValue: (key, value) => video[key] = value,
      ),
      1,
    );
    expect(video['cacheVideoFit'], 1);
  });
}
