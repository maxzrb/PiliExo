import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Player extends Fake implements PlPlayerController {
  _Player(Map<String, dynamic> input)
    : isMedia3Hdr = input['active'],
      currentPosition = Duration(milliseconds: input['position']),
      playWhenReady = input['autoplay'],
      isPlaying = input['playing'] ?? input['autoplay'],
      processing = input['processing'] ?? false;

  @override
  final brightness = 0.0.obs;
  @override
  final dataStatus = DataStatus.loaded.obs;
  @override
  bool isMedia3Hdr;
  @override
  final Duration currentPosition;
  @override
  final bool playWhenReady;
  @override
  final bool isPlaying;
  @override
  final bool processing;
}

class _Page extends VideoDetailController {
  _Page(this.backend, this.input) : super(playerController: backend) {
    isQuerying = input['querying'] ?? false;
  }

  final _Player backend;
  final Map<String, dynamic> input;
  final calls = <List<Object?>>[];
  final releaseLoad = Completer<void>();

  @override
  bool get canSwitchHdrPlayer => true;

  // 仅替换原生加载边界，热切换入口及互斥逻辑仍使用真实页面代码。
  @override
  Future<void> playerInit({
    bool? autoplay,
    bool autoFullScreenFlag = false,
    Duration? resumePosition,
  }) async {
    calls.add([useMedia3Hdr, resumePosition?.inMilliseconds, autoplay]);
    await releaseLoad.future;
    switch (input['outcome']) {
      case 'success':
        backend.isMedia3Hdr = !backend.isMedia3Hdr;
      case 'fallback':
        backend.isMedia3Hdr = false;
      case 'error':
        backend.dataStatus.value = DataStatus.error;
      case 'throw':
        throw StateError('固定失败样例');
    }
  }
}

void main() {
  final inputs = jsonDecode(
    File('test/fixtures/hdr_player_switch/input.json').readAsStringSync(
      encoding: utf8,
    ),
  ) as List;
  final references = jsonDecode(
    File('test/fixtures/hdr_player_switch/reference.json').readAsStringSync(
      encoding: utf8,
    ),
  ) as List;
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('hdr-switch-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    await GStorage.setting.put(SettingBoxKey.enableMedia3Hdr, false);
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (var i = 0; i < inputs.length; i++) {
    final input = inputs[i] as Map<String, dynamic>;
    testWidgets('固定样例：${input['name']}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const SizedBox.shrink(),
        ),
      );
      final player = _Player(input);
      final page = _Page(player, input);
      final pending = page.switchHdrPlayer();
      if (input['repeat'] == true) await page.switchHdrPlayer();
      page.releaseLoad.complete();
      await pending;
      expect({
        'calls': page.calls,
        'active': player.isMedia3Hdr,
        'useMedia3': page.useMedia3Hdr,
      }, references[i]);
      expect(page.switchingPlayer.value, isFalse);
      expect(GStorage.setting.get(SettingBoxKey.enableMedia3Hdr), isFalse);
      unawaited(SmartDialog.dismiss(status: SmartStatus.allToast));
      await tester.pumpAndSettle();
    });
  }
}
