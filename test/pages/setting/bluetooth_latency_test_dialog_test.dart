import 'dart:io';

import 'package:PiliPlus/pages/setting/pages/bluetooth_latency_set.dart';
import 'package:PiliPlus/pages/setting/widgets/bluetooth_latency_test_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/models/bluetooth_latency.dart';
import 'package:PiliPlus/plugin/pl_player/utils/bluetooth_latency_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const connected = BluetoothAudioInfo(
    isBluetooth: true,
    connected: true,
    active: true,
    protocol: BluetoothAudioProtocol.a2dp,
    refreshRate: 60,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-calibration-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() async {
    await GStorage.setting.putAll({
      SettingBoxKey.bluetoothLatencyCompensation: true,
      SettingBoxKey.bluetoothLatencyTrimMs: 100,
    });
  });
  tearDownAll(() async {
    await GStorage.setting.close();
    await directory.delete(recursive: true);
  });

  testWidgets('补偿开关使用右侧布局，断开时变灰、重连时恢复', (tester) async {
    final info = BluetoothLatencyService.instance.info;
    addTearDown(() => info.value = null);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          listTileTheme: const ListTileThemeData(
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        home: const BluetoothLatencySettingPage(),
      ),
    );
    await tester.pumpAndSettle();

    final control = find.byType(Switch);
    final icon = find.byIcon(Icons.bluetooth_rounded);
    expect(
      tester.getCenter(control).dx,
      greaterThan(tester.getCenter(icon).dx),
    );
    expect(tester.widget<Switch>(control).value, isTrue);
    expect(tester.widget<Switch>(control).onChanged, isNull);
    expect(find.text('额外补偿'), findsNothing);

    info.value = connected;
    await tester.pump();
    expect(tester.widget<Switch>(control).value, isTrue);
    expect(tester.widget<Switch>(control).onChanged, isNotNull);
    expect(find.text('额外补偿'), findsOneWidget);

    info.value = BluetoothAudioInfo.none;
    await tester.pump();
    expect(tester.widget<Switch>(control).value, isTrue);
    expect(tester.widget<Switch>(control).onChanged, isNull);
    expect(find.text('额外补偿'), findsNothing);
    expect(
      GStorage.setting.get(SettingBoxKey.bluetoothLatencyCompensation),
      isTrue,
    );
    expect(GStorage.setting.get(SettingBoxKey.bluetoothLatencyTrimMs), 100);
  });

  testWidgets('滑杆微调当前预览，保存时停止测试', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final info = BluetoothLatencyService.instance.info..value = connected;
    addTearDown(() => info.value = null);

    late MockStreamHandlerEventSink cues;
    var starts = 0;
    var stops = 0;
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.maxzrb.piliexo/bluetooth_latency/calibration'),
      MockStreamHandler.inline(
        onListen: (_, sink) {
          starts++;
          cues = sink;
        },
        onCancel: (_) => stops++,
      ),
    );

    int? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<int>(
                context: context,
                builder: (_) =>
                    const BluetoothLatencyTestDialog(initialTrimMs: 100),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).value, 100);
    expect(
      tester.getSize(slider).width,
      tester
          .getSize(find.byKey(const ValueKey('bluetooth-calibration-flash')))
          .width,
    );
    for (final label in ['声音先到', '声音后到']) {
      expect(find.text(label), findsOneWidget);
      expect(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
        findsNothing,
      );
    }
    await tester.tap(find.text('开始校准'));
    await tester.pump();
    expect(starts, 1);

    final firstCue =
        tester.binding.currentSystemFrameTimeStamp.inMicroseconds + 1000000;
    final flash = find.byIcon(Icons.volume_up_rounded);
    cues.success(firstCue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1286));
    expect(flash, findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(flash, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 259));
    expect(flash, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(flash, findsNothing);

    await tester.drag(slider, const Offset(45, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, greaterThan(100));
    final sliderBounds = tester.getRect(slider);
    await tester.tapAt(Offset(sliderBounds.right - 1, sliderBounds.center.dy));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 250);
    cues.success(firstCue + 3000000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2889));
    expect(flash, findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(flash, findsOneWidget);

    await tester.tapAt(sliderBounds.center);
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 0);
    await tester.tapAt(Offset(sliderBounds.left + 1, sliderBounds.center.dy));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, -250);
    expect(starts, 1);

    info.value = BluetoothAudioInfo.none;
    await tester.pump();
    expect(stops, 1);
    expect(flash, findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '开始校准'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, -250);
    expect(stops, 1);
  });
}
