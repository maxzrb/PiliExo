import 'dart:io';

import 'package:PiliPlus/utils/gesture_haptics.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'piliexo-gesture-haptics-test-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await GStorage.setting.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('侧滑震动按设定百分比累计触发', () {
    final tracker = GestureHapticTickTracker();

    tracker.begin(50, stepPercent: 3);
    expect(tracker.update(52.99, stepPercent: 3), isFalse);
    expect(tracker.update(53, stepPercent: 3), isTrue);
    expect(tracker.update(55.99, stepPercent: 3), isFalse);
    expect(tracker.update(56, stepPercent: 3), isTrue);
    expect(tracker.update(53, stepPercent: 3), isTrue);
  });

  test('一次跨过多个刻度只触发一次并保留剩余距离', () {
    final tracker = GestureHapticTickTracker();

    tracker.begin(0, stepPercent: 3);
    expect(tracker.update(7, stepPercent: 3), isTrue);
    expect(tracker.update(8.9, stepPercent: 3), isFalse);
    expect(tracker.update(9, stepPercent: 3), isTrue);
  });

  test('刻度值限制在 1 到 20 的可调范围', () {
    expect(normalizeGestureHapticStepPercent(0), 1);
    expect(normalizeGestureHapticStepPercent(3), 3);
    expect(normalizeGestureHapticStepPercent(99), 20);
  });

  test('音量滑动震动默认开启、亮度滑动震动默认关闭且刻度默认 3%', () async {
    await GStorage.setting.delete(SettingBoxKey.enableVolumeSlideFeedback);
    await GStorage.setting.delete(SettingBoxKey.enableBrightnessSlideFeedback);
    await GStorage.setting.delete(SettingBoxKey.volumeSlideFeedbackStep);
    await GStorage.setting.delete(SettingBoxKey.brightnessSlideFeedbackStep);

    expect(Pref.enableVolumeSlideFeedback, isTrue);
    expect(Pref.enableBrightnessSlideFeedback, isFalse);
    expect(Pref.volumeSlideFeedbackStep, 3);
    expect(Pref.brightnessSlideFeedbackStep, 3);
  });

  test('音量和亮度滑动震动设置可以分别持久化', () async {
    await GStorage.setting.put(SettingBoxKey.enableVolumeSlideFeedback, false);
    await GStorage.setting.put(
      SettingBoxKey.enableBrightnessSlideFeedback,
      true,
    );
    await GStorage.setting.put(SettingBoxKey.volumeSlideFeedbackStep, 7);
    await GStorage.setting.put(SettingBoxKey.brightnessSlideFeedbackStep, 11);

    expect(Pref.enableVolumeSlideFeedback, isFalse);
    expect(Pref.enableBrightnessSlideFeedback, isTrue);
    expect(Pref.volumeSlideFeedbackStep, 7);
    expect(Pref.brightnessSlideFeedbackStep, 11);
  });
}
