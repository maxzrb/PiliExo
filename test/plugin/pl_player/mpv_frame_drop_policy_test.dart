import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/utils/mpv_frame_drop_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = jsonDecode(
    File('test/fixtures/mpv_frame_drop_policy/input.json').readAsStringSync(),
  ) as List;
  final reference = jsonDecode(
    File(
      'test/fixtures/mpv_frame_drop_policy/reference.json',
    ).readAsStringSync(),
  ) as List;

  for (var index = 0; index < input.length; index++) {
    final sample = input[index] as Map<String, dynamic>;
    test(sample['name'] as String, () {
      final speed = (sample['speed'] as num?)?.toDouble() ?? double.nan;
      expect(
        MpvFrameDropPolicy.optionFor(
          nativeHdr: sample['nativeHdr'] as bool,
          hdrCompatibility: sample['hdrCompatibility'] == true,
          speed: speed,
        ),
        reference[index],
      );
    });
  }
}
