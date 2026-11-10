import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/models/mpv_hdr_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('固定输入区分原生硬解直出和软件 GPU 颜色修正', () {
    final cases = jsonDecode(
      File('test/fixtures/mpv_hdr/output-routes.json')
          .readAsStringSync(encoding: utf8),
    ) as List;
    final actual = cases
        .cast<Map<String, dynamic>>()
        .map((sample) {
          final profile5 = sample['profile5'] as bool;
          final hardware = sample['hardwareEnabled'] as bool;
          final direct = MpvHdrPolicy.directOutput(
            profile5: profile5,
            hardwareEnabled: hardware,
          );
          final options = MpvHdrPolicy.options(
            profile5: profile5,
            hardwareEnabled: hardware,
          );
          return '${sample['id']}=${direct ? 'mediacodec_embed' : 'gpu-next'},${options['hwdec']}';
        })
        .join('\n');
    expect(
      '$actual\n',
      File('test/ref/fate/mpv-hdr-output-routes')
          .readAsStringSync(encoding: utf8),
    );
  });

  test('像素格式缺失不冒充软解，使用实际 hwdec-current 固定样例', () {
    final cases = jsonDecode(
      File('test/fixtures/mpv_hdr/decoder-modes.json').readAsStringSync(
        encoding: utf8,
      ),
    ) as List;
    final actual = cases
        .cast<Map<String, dynamic>>()
        .map((sample) {
          return '${sample['id']}=${MpvHdrPolicy.decoderType(sample['current'] as String?)}';
        })
        .join('\n');
    expect(
      '$actual\n',
      File('test/ref/fate/mpv-hdr-decoder-modes').readAsStringSync(
        encoding: utf8,
      ),
    );
  });

  test('固定 Codec String 样例区分无 HDR10 基层的 Profile 5', () {
    final cases = jsonDecode(
      File('test/fixtures/mpv_hdr/codecs.json').readAsStringSync(
        encoding: utf8,
      ),
    ) as List;
    for (final sample in cases.cast<Map<String, dynamic>>()) {
      final codec = sample['codec'] as String?;
      expect(
        MpvHdrPolicy.dolbyVisionProfile(codec),
        sample['profile'],
        reason: '$codec 的参考 Profile',
      );
      expect(
        MpvHdrPolicy.needsProfile5Correction(codec),
        sample['softwareCorrection'],
        reason: '$codec 的参考解码策略',
      );
    }
  });

  test('P5 保留 RPU 软件解码，普通 HDR 使用原生硬解且不覆盖音频选项', () {
    final p5 = MpvHdrPolicy.options(profile5: true);
    final hdr10 = MpvHdrPolicy.options(profile5: false);
    expect(p5['hwdec'], 'no');
    expect(hdr10['hwdec'], 'mediacodec');
    for (final options in [p5, hdr10]) {
      expect(options['egl-output-format'], 'rgb10_a2');
      expect(options['android-hdr-signal-passthrough'], 'yes');
      expect(options['target-trc'], 'pq');
      expect(options['target-prim'], 'bt.2020');
      // 保留完整 PQ 信号范围，系统负责面板适配，避免先压到面板峰值再映射一次。
      expect(options['target-peak'], '10000');
      expect(options['tone-mapping'], 'clip');
      expect(options['gamut-mapping-mode'], 'clip');
      expect(options['hdr-compute-peak'], 'no');
      expect(options['inverse-tone-mapping'], 'no');
      expect(options.keys.any((name) => name.startsWith('audio-')), isFalse);
      expect(options.containsKey('ao'), isFalse);
      expect(options.containsKey('autosync'), isFalse);
      // 普通构建不循环媒体；只有固定真机回归使用编译参数开启循环输入。
      expect(options.containsKey('loop-file'), isFalse);
    }
  });
}
