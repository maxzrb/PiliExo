import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart';

import 'package:PiliPlus/plugin/pl_player/utils/mpv_runtime_metrics.dart';

/// 用独立客户端接收属性事件，不消费 media-kit 的事件队列。
///
/// 复用播放期间已有的每秒采样，不增加计时器或同步属性查询。
/// 必须在主播放器销毁前释放此客户端，否则它会阻止核心退出。
class MpvRuntimeObserver {
  MpvRuntimeObserver._(this._client, this._onTraceEvent);

  Pointer<mpv.mpv_handle> _client;
  final void Function(String, Map<String, Object?>)? _onTraceEvent;
  final traceProperties = <String, Object?>{};
  final metrics = MpvRuntimeMetrics();

  static const _traceProperties = <(String, int)>[
    ('time-pos', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('audio-pts', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('avsync', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('seeking', mpv.mpv_format.MPV_FORMAT_FLAG),
    ('core-idle', mpv.mpv_format.MPV_FORMAT_FLAG),
    ('paused-for-cache', mpv.mpv_format.MPV_FORMAT_FLAG),
    ('pause', mpv.mpv_format.MPV_FORMAT_FLAG),
    ('eof-reached', mpv.mpv_format.MPV_FORMAT_FLAG),
    ('vo-configured', mpv.mpv_format.MPV_FORMAT_FLAG),
    ('current-vo', mpv.mpv_format.MPV_FORMAT_STRING),
    ('hwdec-current', mpv.mpv_format.MPV_FORMAT_STRING),
    ('video-out-params/w', mpv.mpv_format.MPV_FORMAT_INT64),
    ('video-out-params/h', mpv.mpv_format.MPV_FORMAT_INT64),
    ('demuxer-cache-time', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('demuxer-cache-duration', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('cache-buffering-state', mpv.mpv_format.MPV_FORMAT_INT64),
    ('piliexo-insight-vo-drop-count', mpv.mpv_format.MPV_FORMAT_INT64),
  ];

  static const _insightProperties = <(String, int)>[
    ('piliexo-insight-vo-drop-count', mpv.mpv_format.MPV_FORMAT_INT64),
    ('decoder-frame-drop-count', mpv.mpv_format.MPV_FORMAT_INT64),
    ('demuxer-cache-state/fw-bytes', mpv.mpv_format.MPV_FORMAT_INT64),
    ('demuxer-cache-state/cache-duration', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('container-fps', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ('video-format', mpv.mpv_format.MPV_FORMAT_STRING),
    ('audio-codec-name', mpv.mpv_format.MPV_FORMAT_STRING),
    ('current-tracks/video/decoder-desc', mpv.mpv_format.MPV_FORMAT_STRING),
    ('current-tracks/audio/decoder-desc', mpv.mpv_format.MPV_FORMAT_STRING),
  ];

  static MpvRuntimeObserver? create(
    NativePlayer player, {
    void Function(String, Map<String, Object?>)? onTraceEvent,
  }) {
    final name = (onTraceEvent == null ? 'piliexo_insight' : 'piliexo_trace')
        .toNativeUtf8();
    final Pointer<mpv.mpv_handle> client;
    try {
      client = NativePlayer.mpv.mpv_create_client(player.ctx, name);
    } finally {
      malloc.free(name);
    }
    if (client == nullptr) return null;
    final observer = MpvRuntimeObserver._(client, onTraceEvent);
    if (onTraceEvent != null) {
      final level = 'v'.toNativeUtf8();
      try {
        NativePlayer.mpv.mpv_request_log_messages(client, level);
      } finally {
        malloc.free(level);
      }
    }
    final properties = onTraceEvent == null
        ? _insightProperties
        : _traceProperties;
    for (var index = 0; index < properties.length; index++) {
      final (property, format) = properties[index];
      final pointer = property.toNativeUtf8();
      final int result;
      try {
        result = NativePlayer.mpv.mpv_observe_property(
          client,
          index + 1,
          pointer,
          format,
        );
      } finally {
        malloc.free(pointer);
      }
      if (onTraceEvent == null && result < 0 && index < 4) {
        observer.dispose();
        return null;
      }
    }
    return observer;
  }

  void poll() {
    if (_client == nullptr) return;
    // 属性变化会合并；限制单次排空数量，避免异常事件挤占界面线程。
    for (var index = 0; index < 32; index++) {
      final event = NativePlayer.mpv.mpv_wait_event(_client, 0).ref;
      if (event.event_id == mpv.mpv_event_id.MPV_EVENT_NONE) break;
      if (event.event_id == mpv.mpv_event_id.MPV_EVENT_SHUTDOWN) {
        dispose();
        break;
      }
      if (event.event_id != mpv.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE) {
        if (_onTraceEvent != null) _traceEvent(event);
        continue;
      }
      if (event.data == nullptr) continue;
      final property = event.data.cast<mpv.mpv_event_property>().ref;
      final available = property.data != nullptr;
      final integer =
          available && property.format == mpv.mpv_format.MPV_FORMAT_INT64
          ? property.data.cast<Int64>().value
          : null;
      final decimal =
          available && property.format == mpv.mpv_format.MPV_FORMAT_DOUBLE
          ? property.data.cast<Double>().value
          : null;
      final stringPointer =
          available && property.format == mpv.mpv_format.MPV_FORMAT_STRING
          ? property.data.cast<Pointer<Uint8>>().value
          : nullptr;
      final string = stringPointer == nullptr
          ? null
          : stringPointer.toDartString();
      if (_onTraceEvent != null) {
        final traceIndex = event.reply_userdata - 1;
        if (traceIndex < 0 || traceIndex >= _traceProperties.length) continue;
        final flag =
            available && property.format == mpv.mpv_format.MPV_FORMAT_FLAG
            ? property.data.cast<Int32>().value != 0
            : null;
        traceProperties[_traceProperties[traceIndex].$1] =
            integer ??
            (decimal?.isFinite == true ? decimal : null) ??
            string ??
            flag;
        continue;
      }
      switch (event.reply_userdata) {
        case 1:
          metrics.outputDroppedFrames = integer;
        case 2:
          metrics.decoderDroppedFrames = integer;
        case 3:
          metrics.forwardBytes = integer;
        case 4:
          metrics.cacheDuration = decimal;
        case 5:
          metrics.videoFrameRate = decimal;
        case 6:
          metrics.videoCodec = string;
        case 7:
          metrics.audioCodec = string;
        case 8:
          metrics.videoDecoder = string;
        case 9:
          metrics.audioDecoder = string;
      }
    }
    metrics.finishSample();
  }

  void _traceEvent(mpv.mpv_event event) {
    if (event.event_id == mpv.mpv_event_id.MPV_EVENT_LOG_MESSAGE &&
        event.data != nullptr) {
      final log = event.data.cast<mpv.mpv_event_log_message>().ref;
      final message = log.text.toDartString().toLowerCase();
      // 只输出固定分类，原始消息可能携带签名媒体地址。
      final diagnostic = switch (message) {
        _ when message.contains('resuming demuxer to end of cached range') =>
          'resume_cached_range',
        _ when message.contains('cached seek not possible') =>
          'cached_seek_unavailable',
        _ when message.contains('seek failed') => 'demux_seek_failed',
        _ when message.contains('too many packets in the demuxer') =>
          'demux_queue_full',
        _
            when message.contains('connection timed out') ||
                message.contains('connection reset') ||
                message.contains('http error') ||
                message.contains('error reading') =>
          'read_failed',
        _ => null,
      };
      if (diagnostic != null) {
        _onTraceEvent!('mpv.demux', {'reason': diagnostic});
      }
      return;
    }
    final name = switch (event.event_id) {
      mpv.mpv_event_id.MPV_EVENT_START_FILE => 'start',
      mpv.mpv_event_id.MPV_EVENT_FILE_LOADED => 'loaded',
      mpv.mpv_event_id.MPV_EVENT_VIDEO_RECONFIG => 'video_reconfig',
      mpv.mpv_event_id.MPV_EVENT_AUDIO_RECONFIG => 'audio_reconfig',
      mpv.mpv_event_id.MPV_EVENT_SEEK => 'seek',
      mpv.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART => 'playback_restart',
      mpv.mpv_event_id.MPV_EVENT_END_FILE => 'end',
      mpv.mpv_event_id.MPV_EVENT_QUEUE_OVERFLOW => 'queue_overflow',
      _ => null,
    };
    if (name == null) return;
    final end =
        event.event_id == mpv.mpv_event_id.MPV_EVENT_END_FILE &&
            event.data != nullptr
        ? event.data.cast<mpv.mpv_event_end_file>().ref
        : null;
    _onTraceEvent!('mpv.$name', {
      if (end != null) 'reason': end.reason,
      if (end != null) 'error': end.error,
    });
  }

  void dispose() {
    if (_client == nullptr) return;
    final client = _client;
    _client = nullptr;
    NativePlayer.mpv.mpv_destroy(client);
  }
}
