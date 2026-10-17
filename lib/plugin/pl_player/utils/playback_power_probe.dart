import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/plugin/pl_player/backends/media3_hdr.dart';
import 'package:PiliPlus/plugin/pl_player/models/ambient_frame.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_telemetry.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

/// 仅显式编译的研究包使用；正式构建不注册回调、不改变设置。
class PlaybackPowerProbe {
  static const enabled = bool.fromEnvironment('PILI_POWER_PROBE');
  // 只切换研究后端，不启动ABBA、定时取样或自动seek，供系统调度追踪使用。
  static const traceOnly = bool.fromEnvironment('PILI_POWER_TRACE_ONLY');
  static const media3Sdr =
      enabled && bool.fromEnvironment('PILI_POWER_MEDIA3_SDR');
  static const compareOperatingRate =
      enabled && bool.fromEnvironment('PILI_POWER_COMPARE_OPERATING_RATE');
  static final ambientEnabled = ValueNotifier(true);
  static int ambientCaptures = 0;
  static int ambientCaptureUs = 0;

  bool _cancelled = false;
  int _frames = 0;
  int _buildUs = 0;
  int _rasterUs = 0;
  int _maxRasterUs = 0;

  void cancel() => _cancelled = true;

  void _timings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frames++;
      _buildUs += timing.buildDuration.inMicroseconds;
      _rasterUs += timing.rasterDuration.inMicroseconds;
      if (timing.rasterDuration.inMicroseconds > _maxRasterUs) {
        _maxRasterUs = timing.rasterDuration.inMicroseconds;
      }
    }
  }

  void _event(String event, Map<String, Object?> values) {
    debugPrint(
      'PILI_POWER ${jsonEncode({
        'event': event,
        'epochMs': DateTime.now().millisecondsSinceEpoch,
        ...values,
      })}',
    );
  }

  /// 每个窗口先回到同一位置，再预热；ABBA抵消一部分时间顺序影响。
  Future<void> run({
    Player? player,
    HdrMedia3Controller? media3,
    required String? sourceFrameRate,
    required PlaybackTelemetry Function() telemetry,
    required int? Function() ambientTextureId,
    required bool Function() isCurrent,
    required Future<void> Function() resetSegment,
  }) async {
    if (!enabled || traceOnly) return;
    assert((player == null) != (media3 == null));
    final originalSync = player?.getProperty('video-sync') ?? 'Media3 clock';
    final originalOptimized = AmbientFramePolicy.optimized.value;
    final originalDecoderOptions = player?.getProperty('vd-lavc-o');
    final originalVideoTrack = player?.getProperty('vid');
    int positionMs() =>
        player?.state.position.inMilliseconds ??
        media3!.position.inMilliseconds;
    bool playing() => player?.state.playing ?? media3!.isPlaying;
    bool wantsPlayback() => player?.state.playing ?? media3!.playWhenReady;
    Object? read(String property) {
      if (player != null) {
        final raw = player.getProperty(property);
        return num.tryParse(raw) ?? raw;
      }
      return switch (property) {
        'frame-drop-count' => telemetry().droppedFrames,
        _ => null,
      };
    }

    bool active() => !_cancelled && isCurrent();
    Future<void> wait(int seconds) async {
      for (var index = 0; index < seconds; index++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!active()) throw StateError('页面或素材已改变，实验取消');
        if (!wantsPlayback()) throw StateError('播放已暂停，实验取消');
      }
    }

    SchedulerBinding.instance.addTimingsCallback(_timings);
    try {
      if (compareOperatingRate &&
          (player == null ||
              AmbientFramePolicy.compare ||
              AmbientFramePolicy.gpuTexture)) {
        throw StateError('硬解预留对照仅支持mpv，且不能混合环境光实现对照');
      }
      // 留出页面挂载和用户确认时间，不与起播动画混算。
      await wait(10);
      _event('start', {
        'originalSync': originalSync,
        'engine': player == null ? 'Media3 SurfaceView' : 'mpv GPU texture',
        'hwdec':
            player?.getProperty('hwdec-current') ?? telemetry().videoDecoder,
        'vo': player?.getProperty('vo') ?? 'SurfaceView',
        'decoderOptions': player?.getProperty('vd-lavc-o'),
        'sourceFps': double.tryParse(sourceFrameRate ?? ''),
      });
      for (final group
          in (compareOperatingRate
              ? ['operating-rate']
              : (player == null || AmbientFramePolicy.compare
                    ? ['ambient']
                    : ['ambient', 'sync']))) {
        var round = 0;
        for (final variant in ['A', 'B', 'B', 'A']) {
          if (!active()) throw StateError('实验取消');
          final label = '$group-${++round}-$variant';
          final operatingRateTarget = compareOperatingRate
              ? (variant == 'A' ? 180 : 60)
              : null;
          if (operatingRateTarget != null) {
            _event('decoder_reset_start', {
              'label': label,
              'targetOperatingRate': operatingRateTarget,
            });
            // 仅在研究窗口之外切换轨道以重建解码器，不用于手势切速。
            player!.setProperty(
              'vd-lavc-o',
              'operating_rate=$operatingRateTarget',
            );
            player.setProperty('vid', 'no');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (!active()) throw StateError('重建期间页面或素材已改变');
            player.setProperty('vid', originalVideoTrack!);
          }
          final capture =
              compareOperatingRate ||
              group == 'ambient' &&
                  (AmbientFramePolicy.compare || variant == 'A');
          if (AmbientFramePolicy.compare) {
            AmbientFramePolicy.optimized.value = variant == 'B';
          }
          final sync = group == 'sync' && variant == 'B'
              ? 'audio'
              : originalSync;
          ambientEnabled.value = capture;
          player?.setProperty('video-sync', sync);
          await resetSegment();
          // 按媒体位置对齐窗口，避免首轮seek缓冲令固定墙钟预热不足。
          await wait(1);
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (positionMs() < 68000 || !playing()) {
            if (DateTime.now().isAfter(deadline)) throw StateError('预热未推进到68秒');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (!active() || !wantsPlayback()) throw StateError('预热被中断');
          }
          if (positionMs() > 68500) throw StateError('测量窗口起点偏移');
          _frames = _buildUs = _rasterUs = _maxRasterUs = 0;
          ambientCaptures = ambientCaptureUs = 0;
          _event('phase_start', {
            'label': label,
            'operatingRateTarget': operatingRateTarget,
            'decoderOptions': player?.getProperty('vd-lavc-o'),
            'hwdec': player?.getProperty('hwdec-current'),
            'ambient': capture,
            'optimizedAmbient': AmbientFramePolicy.optimized.value,
            'gpuTextureExperiment': AmbientFramePolicy.gpuTexture,
            'compareAmbient': AmbientFramePolicy.compare,
            'ambientImplementation': player == null
                ? (AmbientFramePolicy.optimized.value ? 'rgba' : 'snapshot')
                : (AmbientFramePolicy.gpuTexture &&
                          AmbientFramePolicy.optimized.value
                      ? 'gpu-texture'
                      : 'snapshot'),
            'videoSync': player?.getProperty('video-sync') ?? 'Media3 clock',
            'positionMs': positionMs(),
            'sourceFps': double.tryParse(sourceFrameRate ?? ''),
          });
          for (var index = 0; index < 20; index++) {
            await wait(1);
            final clock = Stopwatch()..start();
            final values = <String, Object?>{};
            for (final property in const [
              'avsync',
              'frame-drop-count',
              'decoder-frame-drop-count',
              'display-sync-active',
              'estimated-display-fps',
            ]) {
              values[property] = read(property);
            }
            _event('sample', {
              'label': label,
              'positionMs': positionMs(),
              'speed': player?.state.rate ?? media3!.speed,
              'buffering': player?.state.buffering ?? media3!.isBuffering,
              'width': player?.state.width ?? media3!.width,
              'height': player?.state.height ?? media3!.height,
              'queryUs': clock.elapsedMicroseconds,
              'ambientTextureId': ambientTextureId(),
              ...values,
            });
          }
          _event('phase_end', {
            'label': label,
            'positionMs': positionMs(),
            'flutterFrames': _frames,
            'buildUs': _buildUs,
            'rasterUs': _rasterUs,
            'maxRasterUs': _maxRasterUs,
            'ambientCaptures': ambientCaptures,
            'ambientCaptureUs': ambientCaptureUs,
          });
          if (AmbientFramePolicy.compare) await wait(1);
        }
      }
      _event('complete', {});
    } catch (error) {
      _event('aborted', {'reason': '$error'});
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      ambientEnabled.value = true;
      AmbientFramePolicy.optimized.value = originalOptimized;
      // 不对已经切走的素材写回属性，也不持久化实验设置。
      if (isCurrent()) {
        player?.setProperty('video-sync', originalSync);
        if (compareOperatingRate && player != null) {
          try {
            player.setProperty('vd-lavc-o', originalDecoderOptions!);
            player.setProperty('vid', 'no');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (isCurrent()) player.setProperty('vid', originalVideoTrack!);
          } catch (error) {
            _event('restore_failed', {'reason': '$error'});
          }
        }
      }
    }
  }
}
