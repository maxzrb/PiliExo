import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:media_kit/media_kit.dart';

import 'package:PiliPlus/plugin/pl_player/utils/playback_experiment.dart';

/// 只在显式诊断构建中比较切速过渡；不写用户设置，不降低视频帧率。
class PlaybackTransitionProbe {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<void> run({
    required NativePlayer player,
    required Future<void> Function(double) setRate,
    required bool Function() isCurrent,
    required PlaybackExperimentRecorder recorder,
  }) async {
    if (!PlaybackExperiment.transitionProbe) return;
    bool active() => !_cancelled && isCurrent();
    final configDir = await getExternalStorageDirectory();
    final configFile = configDir == null
        ? null
        : File('${configDir.path}/piliexo_transition_probe.json');
    final config = configFile != null && await configFile.exists()
        ? jsonDecode(await configFile.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{};
    final requestedVariants = (config['variants'] as List?)
        ?.cast<Map<String, dynamic>>();
    final additionalKeys =
        requestedVariants
            ?.expand((v) => ((v['options'] as Map?) ?? {}).keys.cast<String>())
            .toSet() ??
        <String>{};
    final original = <String, String>{
      for (final key in [
        'ao',
        'audio-buffer',
        'video-sync',
        'audio-pitch-correction',
        'opensles-buffer-size-in-ms',
        'aaudio-performance-mode',
        'aaudio-buffer-capacity',
        ...additionalKeys,
      ])
        key: player.getProperty('options/$key'),
    };
    try {
      await Future<void>.delayed(const Duration(seconds: 4));
      final defaults = [
        (
          name: 'audiotrack-200',
          ao: 'audiotrack',
          buffer: '0.2',
          options: <String, String>{},
        ),
        (
          name: 'audiotrack-50',
          ao: 'audiotrack',
          buffer: '0.05',
          options: <String, String>{},
        ),
        (
          name: 'opensles-driver50',
          ao: 'opensles',
          buffer: '0.05',
          options: <String, String>{'opensles-buffer-size-in-ms': '50'},
        ),
        (
          name: 'opensles-driver20',
          ao: 'opensles',
          buffer: '0.02',
          options: <String, String>{'opensles-buffer-size-in-ms': '20'},
        ),
        (
          name: 'aaudio-lowlatency',
          ao: 'aaudio',
          buffer: '0.05',
          options: <String, String>{'aaudio-performance-mode': 'low-latency'},
        ),
        (
          name: 'aaudio-lowlatency-1024',
          ao: 'aaudio',
          buffer: '0.05',
          options: <String, String>{
            'aaudio-performance-mode': 'low-latency',
            'aaudio-buffer-capacity': '1024',
          },
        ),
        (
          name: 'aaudio-lowlatency-512',
          ao: 'aaudio',
          buffer: '0.02',
          options: <String, String>{
            'aaudio-performance-mode': 'low-latency',
            'aaudio-buffer-capacity': '512',
          },
        ),
        (
          name: 'audiotrack-200-reverse',
          ao: 'audiotrack',
          buffer: '0.2',
          options: <String, String>{},
        ),
      ];
      final variants = requestedVariants == null
          ? defaults
          : [
              for (final v in requestedVariants)
                (
                  name: v['name'] as String,
                  ao: v['ao'] as String,
                  buffer: v['buffer'] as String,
                  options: Map<String, String>.from(v['options'] as Map? ?? {}),
                ),
            ];
      for (final variant in variants) {
        if (!active()) return;
        for (final entry in original.entries) {
          player.setProperty(entry.key, entry.value);
        }
        await setRate(1);
        player.setProperty('audio-buffer', variant.buffer);
        player.setProperty('video-sync', 'display-resample');
        for (final entry in variant.options.entries) {
          player.setProperty(entry.key, entry.value);
        }
        // 临时切换输出后再选择候选，确保缓冲选项用于新建的音频输出。
        player.setProperty('ao', 'null');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!active()) return;
        player.setProperty('ao', variant.ao);
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!active()) return;
        recorder.event('transition_variant', {
          'name': variant.name,
          'original': original,
          'requested': variant.options,
          for (final key in variant.options.keys)
            key: player.getProperty('options/$key'),
          for (final key in [
            'current-ao',
            'audio-buffer',
            'video-sync',
            'audio-pitch-correction',
            'af',
            'audio-params',
          ])
            key: player.getProperty(key),
        });
        for (
          var round = 0;
          round < (config['rounds'] as int? ?? 2).clamp(1, 8);
          round++
        ) {
          if (!active()) return;
          recorder.event('transition_normal', {
            'name': variant.name,
            'round': round,
          });
          await Future<void>.delayed(const Duration(seconds: 3));
          if (!active()) return;
          recorder.event('transition_start', {
            'name': variant.name,
            'round': round,
          });
          await setRate(3);
          await Future<void>.delayed(const Duration(seconds: 3));
          if (!active()) return;
          recorder.event('transition_end', {
            'name': variant.name,
            'round': round,
          });
          await setRate(1);
          await Future<void>.delayed(const Duration(seconds: 3));
          if (!active()) return;
          recorder.event('transition_recovered', {
            'name': variant.name,
            'round': round,
          });
        }
      }
      recorder.event('transition_complete', {});
    } catch (error) {
      if (active()) recorder.event('transition_error', {'error': '$error'});
    } finally {
      if (active()) {
        await setRate(1);
        for (final entry in original.entries) {
          player.setProperty(entry.key, entry.value);
        }
      }
    }
  }
}
