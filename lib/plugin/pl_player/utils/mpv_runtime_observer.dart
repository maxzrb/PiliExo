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
  MpvRuntimeObserver._(this._client);

  Pointer<mpv.mpv_handle> _client;
  final metrics = MpvRuntimeMetrics();

  static MpvRuntimeObserver? create(NativePlayer player) {
    final name = 'piliexo_insight'.toNativeUtf8();
    final Pointer<mpv.mpv_handle> client;
    try {
      client = NativePlayer.mpv.mpv_create_client(player.ctx, name);
    } finally {
      malloc.free(name);
    }
    if (client == nullptr) return null;
    final observer = MpvRuntimeObserver._(client);
    const properties = <(String, int)>[
      ('frame-drop-count', mpv.mpv_format.MPV_FORMAT_INT64),
      ('decoder-frame-drop-count', mpv.mpv_format.MPV_FORMAT_INT64),
      ('demuxer-cache-state/fw-bytes', mpv.mpv_format.MPV_FORMAT_INT64),
      ('demuxer-cache-state/cache-duration', mpv.mpv_format.MPV_FORMAT_DOUBLE),
    ];
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
      if (result < 0) {
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
      if (event.event_id != mpv.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE ||
          event.data == nullptr) {
        continue;
      }
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
      switch (event.reply_userdata) {
        case 1:
          metrics.outputDroppedFrames = integer;
        case 2:
          metrics.decoderDroppedFrames = integer;
        case 3:
          metrics.forwardBytes = integer;
        case 4:
          metrics.cacheDuration = decimal;
      }
    }
    metrics.finishSample();
  }

  void dispose() {
    if (_client == nullptr) return;
    final client = _client;
    _client = nullptr;
    NativePlayer.mpv.mpv_destroy(client);
  }
}
