import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/models/hdr_playback_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('路线偏好固定输入：继承旧开关且显式选择优先', () {
    final samples = jsonDecode(
      File('test/fixtures/mpv_hdr/route-preferences.json')
          .readAsStringSync(encoding: utf8),
    ) as List;
    final actual = samples
        .cast<Map<String, dynamic>>()
        .map((sample) {
          final route = HdrPlaybackRoute.resolve(
            stored: sample['stored'],
            legacyMedia3: sample['media3'] as bool,
            legacyMpv: sample['mpv'] as bool,
          );
          return '${sample['id']}=${route.storageValue}';
        })
        .join('\n');
    expect(
      '$actual\n',
      File('test/ref/fate/mpv-hdr-route-preferences')
          .readAsStringSync(encoding: utf8),
    );
  });
}
