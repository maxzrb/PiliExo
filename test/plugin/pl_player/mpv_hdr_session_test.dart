import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/backends/mpv_hdr.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

class _PlayerStream extends Fake implements PlayerStream {
  @override
  Stream<VideoParams> get videoParams => const Stream.empty();
}

class _NativePlayer extends Fake implements NativePlayer {
  @override
  int get handle => 1;

  @override
  PlayerStream get stream => _PlayerStream();
}

String reference(String name) =>
    File('test/ref/fate/$name').readAsStringSync(encoding: utf8);

List<dynamic> fixture(String name) => jsonDecode(
  File('test/fixtures/mpv_hdr/$name.json').readAsStringSync(encoding: utf8),
) as List;

MpvHdrController controller() => MpvHdrController(
  _NativePlayer(),
  codecs: 'hev1.2.4.L153.B0',
  hardwareEnabled: true,
  qualityCode: 125,
  width: 1920,
  height: 1080,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.maxzrb.piliexo/mpv_hdr');
  const events = MethodChannel('com.maxzrb.piliexo/mpv_hdr/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(methods, null)
      ..setMockMethodCallHandler(events, null);
  });

  test('固定切源输入：画质、尺寸、硬解或编码变化均重建会话', () async {
    final output = controller();
    final actual = StringBuffer();
    for (final sample in fixture('session-reuse')) {
      final config = <String, dynamic>{
        'codecs': output.codecs,
        'hardwareEnabled': true,
        'qualityCode': 125,
        'width': 1920,
        'height': 1080,
        ...Map<String, dynamic>.from(sample['changes'] as Map),
      };
      final source = HdrNetworkSource(
        useMpvHdr: true,
        qualityCode: config['qualityCode'] as int,
        video: HdrTrackSource(
          urls: const ['https://example.invalid/video'],
          codecs: config['codecs'] as String,
          width: config['width'] as int,
          height: config['height'] as int,
        ),
      );
      final reuse = output.matchesSource(
        source,
        hardwareEnabled: config['hardwareEnabled'] as bool,
      );
      actual.writeln('${sample['id']}=${reuse ? 'reuse' : 'recreate'}');
    }
    expect(actual.toString(), reference('mpv-hdr-session-reuse'));
    await output.dispose();
  });

  test('固定通道输入：解码回调与 operating_rate 同时送入 vd-lavc-o', () async {
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final actual = StringBuffer();
    for (final sample in fixture('decoder-options')) {
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'create') {
          return {'decoderOptions': sample['native']};
        }
        return null;
      });
      final output = controller();
      await output.initialize();
      final existing = Map<String, String>.from(sample['existing'] as Map);
      final merged = output.mediaOptions(existing);
      actual.writeln('${sample['id']}=${merged['vd-lavc-o']}');
      for (final entry in existing.entries) {
        if (entry.key != 'vd-lavc-o') {
          expect(merged[entry.key], entry.value);
        }
      }
      await output.dispose();
    }
    expect(actual.toString(), reference('mpv-hdr-decoder-options'));
  });

  test('旧插件缺少解码参数时明确失败并允许释放，不假报初始化成功', () async {
    messenger.setMockMethodCallHandler(events, (_) async => null);
    var released = false;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'release') released = true;
      return null;
    });
    final output = controller();
    await expectLater(output.initialize(), throwsStateError);
    await output.dispose();
    expect(released, isTrue);
  });
}
