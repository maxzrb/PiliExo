import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Media3 原生桥接事件。
class HdrMedia3Event {
  final String sessionId;
  final String type;
  final Map<String, dynamic> data;

  const HdrMedia3Event({
    required this.sessionId,
    required this.type,
    this.data = const {},
  });

  factory HdrMedia3Event.fromDynamic(dynamic value) {
    final map = Map<String, dynamic>.from(value as Map);
    final sessionId = map.remove('sessionId') as String? ?? '';
    final type = map.remove('type') as String? ?? 'unknown';
    return HdrMedia3Event(sessionId: sessionId, type: type, data: map);
  }

  T? value<T>(String key) => data[key] is T ? data[key] as T : null;
}

/// Media3 HDR 后端的 Flutter 适配器。
///
/// Android 视图通过 Hybrid Composition 创建，原生端固定使用 SurfaceView。
/// 这里不暴露 media_kit 的 Player 状态，播放器控制器只消费统一的事件和快照。
class HdrMedia3Controller {
  static const _methodChannel = MethodChannel(
    'com.example.piliplus/media3_hdr',
  );
  static const _eventChannel = EventChannel(
    'com.example.piliplus/media3_hdr/events',
  );
  static final Stream<HdrMedia3Event> _nativeEvents = _eventChannel
      .receiveBroadcastStream()
      .map(HdrMedia3Event.fromDynamic);
  static int _nextSession = 0;

  final String sessionId =
      'hdr-${DateTime.now().microsecondsSinceEpoch}-${_nextSession++}';
  final StreamController<HdrMedia3Event> _eventController =
      StreamController<HdrMedia3Event>.broadcast();

  StreamSubscription<HdrMedia3Event>? _nativeSubscription;
  bool _created = false;
  bool _released = false;
  HdrNetworkSource? _source;
  String? _subtitleVtt;
  String? _subtitleLanguage;
  String? _subtitleLabel;
  bool _isPlaying = false;
  bool _playWhenReady = false;
  bool _isBuffering = true;
  bool _completed = false;
  bool _firstFrame = false;
  int _positionMs = 0;
  int _bufferedMs = 0;
  int _durationMs = 0;
  int _width = 0;
  int _height = 0;
  double _speed = 1.0;

  bool get isPlaying => _isPlaying;
  bool get playWhenReady => _playWhenReady;
  bool get isBuffering => _isBuffering;
  bool get isCompleted => _completed;
  bool get firstFrameRendered => _firstFrame;
  Duration get position => Duration(milliseconds: _positionMs);
  Duration get bufferedPosition => Duration(milliseconds: _bufferedMs);
  Duration get duration => Duration(milliseconds: _durationMs);
  int get width => _width;
  int get height => _height;
  double get speed => _speed;
  Stream<HdrMedia3Event> get events => _eventController.stream;

  Future<void> initialize() async {
    if (_created) return;
    _nativeSubscription = _nativeEvents
        .where((event) {
          return event.sessionId == sessionId;
        })
        .listen(_handleEvent);
    try {
      await _invoke('createSession');
      _created = true;
    } catch (_) {
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
      rethrow;
    }
  }

  Future<void> load(
    HdrNetworkSource source, {
    Duration startPosition = Duration.zero,
    required bool playWhenReady,
    Duration? duration,
    String? subtitleVtt,
    String? subtitleLanguage,
    String? subtitleLabel,
  }) async {
    await initialize();
    _source = source;
    _subtitleVtt = subtitleVtt;
    _subtitleLanguage = subtitleLanguage;
    _subtitleLabel = subtitleLabel;
    _completed = false;
    _firstFrame = false;
    _playWhenReady = playWhenReady;
    _isPlaying = playWhenReady;
    _speed = 1.0;
    await _invoke('load', {
      'qualityCode': source.qualityCode,
      'video': source.video.toJson(),
      if (source.audio != null) 'audio': source.audio!.toJson(),
      'headers': source.headers,
      if (duration != null) 'durationMs': duration.inMilliseconds,
      'startPositionMs': startPosition.inMilliseconds,
      'playWhenReady': playWhenReady,
      if (subtitleVtt != null) 'subtitleVtt': subtitleVtt,
      if (subtitleLanguage != null) 'subtitleLanguage': subtitleLanguage,
      if (subtitleLabel != null) 'subtitleLabel': subtitleLabel,
    });
  }

  Future<void> play() {
    _playWhenReady = true;
    _isPlaying = true;
    _completed = false;
    return _invoke('play');
  }

  Future<void> pause() {
    _playWhenReady = false;
    _isPlaying = false;
    return _invoke('pause');
  }

  Future<void> seekTo(Duration position) => _invoke('seekTo', {
    'positionMs': position.inMilliseconds.clamp(0, 1 << 62),
  });

  Future<void> setSpeed(double speed) async {
    final value = speed.clamp(0.1, 4.0).toDouble();
    _speed = value;
    await _invoke('setSpeed', {'speed': value});
  }

  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'volume': volume.clamp(0.0, 1.0)});

  Future<void> setResizeMode(String mode) =>
      _invoke('setResizeMode', {'mode': mode});

  Future<void> hideSurface() async {
    if (!_created) return;
    try {
      await _invoke('hideSurface');
    } catch (_) {
      // 页面销毁时原生通道可能已经关闭，清屏失败不应产生未处理异常。
    }
  }

  Future<void> setSubtitle({
    required String vtt,
    String? language,
    String? label,
  }) {
    _subtitleVtt = vtt;
    _subtitleLanguage = language;
    _subtitleLabel = label;
    return _invoke('setSubtitle', {
      'vtt': vtt,
      'language': language,
      'label': label,
    });
  }

  Future<void> clearSubtitle() {
    _subtitleVtt = null;
    _subtitleLanguage = null;
    _subtitleLabel = null;
    return _invoke('clearSubtitle');
  }

  Future<void> setSubtitleStyle({
    required double fontScale,
    required double bottomPadding,
    required double horizontalPadding,
    required double backgroundOpacity,
  }) => _invoke('setSubtitleStyle', {
    'fontScale': fontScale,
    'bottomPadding': bottomPadding,
    'horizontalPadding': horizontalPadding,
    'backgroundOpacity': backgroundOpacity,
  });

  /// 使用当前媒体源从当前位置重载，供 CDN 断流时恢复播放。
  Future<void> reload({bool? playWhenReady}) async {
    final source = _source;
    if (source == null) return;
    final oldSpeed = _speed;
    await load(
      source,
      startPosition: position,
      playWhenReady: playWhenReady ?? _playWhenReady,
      subtitleVtt: _subtitleVtt,
      subtitleLanguage: _subtitleLanguage,
      subtitleLabel: _subtitleLabel,
    );
    if (oldSpeed != 1.0) await setSpeed(oldSpeed);
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_released) return;
    await _methodChannel.invokeMethod<void>(method, {
      'sessionId': sessionId,
      ...?arguments,
    });
  }

  void _handleEvent(HdrMedia3Event event) {
    switch (event.type) {
      case 'position':
        _positionMs = event.value<num>('positionMs')?.toInt() ?? _positionMs;
        _bufferedMs =
            event.value<num>('bufferedPositionMs')?.toInt() ?? _bufferedMs;
        _durationMs = event.value<num>('durationMs')?.toInt() ?? _durationMs;
        break;
      case 'buffered':
        _bufferedMs = event.value<num>('positionMs')?.toInt() ?? _bufferedMs;
        break;
      case 'ready':
        _isBuffering = false;
        _durationMs = event.value<num>('durationMs')?.toInt() ?? _durationMs;
        _width = event.value<num>('width')?.toInt() ?? _width;
        _height = event.value<num>('height')?.toInt() ?? _height;
        break;
      case 'buffering':
        _isBuffering = event.value<bool>('value') ?? _isBuffering;
        break;
      case 'playing':
        _isPlaying = event.value<bool>('value') ?? _isPlaying;
        break;
      case 'completed':
        _completed = true;
        _isPlaying = false;
        _playWhenReady = false;
        break;
      case 'videoSize':
        _width = event.value<num>('width')?.toInt() ?? _width;
        _height = event.value<num>('height')?.toInt() ?? _height;
        break;
      case 'firstFrame':
        _firstFrame = true;
        break;
      case 'error':
        _isBuffering = false;
        break;
    }
    if (!_eventController.isClosed) _eventController.add(event);
  }

  /// 创建原生 SurfaceView。该视图不使用 TextureView、Virtual Display 或 Flutter Texture。
  Widget buildView({Key? key}) {
    return PlatformViewLink(
      key: key,
      viewType: 'piliplus/media3_hdr_surface',
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: 'piliplus/media3_hdr_surface',
          layoutDirection: TextDirection.ltr,
          creationParams: <String, Object?>{'sessionId': sessionId},
          creationParamsCodec: const StandardMessageCodec(),
        );
        controller.addOnPlatformViewCreatedListener(
          params.onPlatformViewCreated,
        );
        controller.create();
        return controller;
      },
    );
  }

  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    if (_created) {
      try {
        await _methodChannel.invokeMethod<void>('releaseSession', {
          'sessionId': sessionId,
        });
      } catch (_) {
        // 页面退出时原生引擎可能已经被 Flutter 销毁，释放失败无需阻塞页面退出。
      }
    }
    _created = false;
    await _eventController.close();
  }
}
