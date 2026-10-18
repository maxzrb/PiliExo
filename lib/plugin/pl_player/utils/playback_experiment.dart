import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 正式构建不采样，运行速率默认使用按素材规划的需求；0保留为对照回退值。
abstract final class PlaybackExperiment {
  static const enabled = bool.fromEnvironment('PILI_PLAYBACK_DIAGNOSTICS');
  static const nativeLogs = bool.fromEnvironment('PILI_MPV_NATIVE_LOGS');
  static const transitionProbe =
      enabled && bool.fromEnvironment('PILI_TRANSITION_PROBE');
  static const sampleMilliseconds = int.fromEnvironment(
    'PILI_PLAYBACK_SAMPLE_MS',
    defaultValue: 500,
  );
  static const operatingRate = int.fromEnvironment(
    'PILI_MPV_OPERATING_RATE',
    defaultValue: -1,
  );

  static int? resolveOperatingRate(int? plannedRate) =>
      operatingRate < 0 ? plannedRate : operatingRate;

  static Map<String, String> decoderOptions({
    required bool isAndroid,
    int? plannedRate,
  }) => {
    // 功耗对照需要关闭诊断采样，同时保留相同的解码运行速率。
    if (isAndroid && (resolveOperatingRate(plannedRate) ?? 0) > 0)
      'vd-lavc-o': 'operating_rate=${resolveOperatingRate(plannedRate)}',
  };
}

/// 诊断中的原生 speed 是配置值，实际推进速度由相邻视频/音频 PTS 推算。
class PlaybackExperimentRecorder {
  final Stopwatch _clock = Stopwatch()..start();
  bool _attached = false;
  int _frames = 0;
  int _maxBuildUs = 0;
  int _maxRasterUs = 0;

  void start() {
    if (!PlaybackExperiment.enabled || _attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frames++;
      if (timing.buildDuration.inMicroseconds > _maxBuildUs) {
        _maxBuildUs = timing.buildDuration.inMicroseconds;
      }
      if (timing.rasterDuration.inMicroseconds > _maxRasterUs) {
        _maxRasterUs = timing.rasterDuration.inMicroseconds;
      }
    }
  }

  void event(String event, Map<String, Object?> values) {
    if (!PlaybackExperiment.enabled) return;
    debugPrintSynchronously(
      'PILI_PLAYBACK ${jsonEncode({
        'event': event,
        'epochMs': DateTime.now().millisecondsSinceEpoch,
        'elapsedUs': _clock.elapsedMicroseconds,
        ...values,
      })}',
    );
  }

  void sample({
    required String Function(String property) readProperty,
    required double targetRate,
    required double baseRate,
    required bool longPress,
    required int positionMs,
  }) {
    if (!PlaybackExperiment.enabled) return;
    final query = Stopwatch()..start();
    final values = <String, Object?>{};
    for (final property in const [
      'speed',
      'audio-pts',
      'video-pts',
      'time-pos',
      'estimated-frame-number',
      'audio-speed-correction',
      'vo-delayed-frame-count',
      'avsync',
      'frame-drop-count',
      'decoder-frame-drop-count',
      'mistimed-frame-count',
      'demuxer-cache-duration',
    ]) {
      try {
        final value = readProperty(property);
        final number = num.tryParse(value);
        values[property] = number?.isFinite == true ? number : null;
      } catch (_) {
        values[property] = null;
      }
    }
    event('sample', {
      'targetRate': targetRate,
      'baseRate': baseRate,
      'longPress': longPress,
      'positionMs': positionMs,
      'queryUs': query.elapsedMicroseconds,
      'flutterFrames': _frames,
      'maxBuildUs': _maxBuildUs,
      'maxRasterUs': _maxRasterUs,
      ...values,
    });
    _frames = _maxBuildUs = _maxRasterUs = 0;
  }

  void dispose() {
    if (!_attached) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _attached = false;
  }
}
