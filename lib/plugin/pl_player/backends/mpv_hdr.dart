import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'package:PiliPlus/plugin/pl_player/models/ambient_frame.dart';
import 'package:PiliPlus/plugin/pl_player/models/mpv_hdr_policy.dart';

/// 复用 media-kit 的播放实例，仅将视频输出接到独立的原生 SurfaceView。
class MpvHdrController {
  MpvHdrController(
    this.player, {
    required this.codecs,
    required this.hardwareEnabled,
    required this.qualityCode,
    this.width,
    this.height,
  });

  static const _methods = MethodChannel('com.maxzrb.piliexo/mpv_hdr');
  static const _events = EventChannel('com.maxzrb.piliexo/mpv_hdr/events');
  static final _stream = _events.receiveBroadcastStream().cast<Map>();
  static int _nextSession = 0;

  final NativePlayer player;
  final String? codecs;
  final bool hardwareEnabled;
  final int qualityCode;
  final int? width;
  final int? height;
  final String sessionId = 'mpv-hdr-${_nextSession++}';
  final diagnostics = ValueNotifier<Map<String, dynamic>>(const {});
  final _errors = StreamController<String>.broadcast();
  StreamSubscription<Map>? _subscription;
  StreamSubscription<VideoParams>? _sizeSubscription;
  bool _released = false;
  bool _created = false;

  Stream<String> get errors => _errors.stream;
  bool get profile5 => MpvHdrPolicy.needsProfile5Correction(codecs);
  bool get directOutput => switch (diagnostics.value['vo']) {
    'mediacodec_embed' => true,
    'gpu-next' => false,
    _ => MpvHdrPolicy.directOutput(
      profile5: profile5,
      hardwareEnabled: hardwareEnabled,
    ),
  };
  String get decoderType => MpvHdrPolicy.decoderType(
    diagnostics.value['hwdec-current']?.toString(),
  );
  String get hdrType {
    final output = diagnostics.value;
    if (output['hdrActive'] != true) return '';
    final dynamicType = switch (output['dynamicMode']) {
      'vivid-sdk' =>
        output['dynamicMetadataActive'] == true
            ? 'HDR Vivid / 动态元数据'
            : 'HDR Vivid / 等待动态元数据',
      'dolby-system' => 'Dolby Vision / 系统动态',
      'dolby-hdr10' =>
        'Dolby Vision P${detectedDolbyVisionProfile ?? '?'} / HDR10 基础',
      'dolby-software' =>
        'Dolby Vision P${detectedDolbyVisionProfile ?? '?'} / HDR10 基础',
      _ => '',
    };
    if (dynamicType.isNotEmpty) return dynamicType;
    final transfer = output['outputTransfer'] == 'hlg' ? 'HLG' : 'PQ';
    final depth = output['vo'] == 'mediacodec_embed'
        ? '原生硬解输出'
        : output['format'] == 43
        ? '10-bit'
        : '浮点输出';
    return '$transfer / $depth';
  }

  int? get detectedDolbyVisionProfile =>
      int.tryParse(
        diagnostics.value['current-tracks/video/dolby-vision-profile']
                ?.toString() ??
            '',
      ) ??
      MpvHdrPolicy.dolbyVisionProfile(codecs);

  Future<void> initialize() async {
    _subscription = _stream
        .where((event) => event['sessionId'] == sessionId)
        .listen((event) {
          if (_released) return;
          final data = Map<String, dynamic>.from(event);
          diagnostics.value = data;
          if (event['type'] == 'error') {
            _errors.add(event['message']?.toString() ?? 'mpv HDR 输出失败');
          }
        });
    try {
      await _methods.invokeMethod<void>('create', {
        'sessionId': sessionId,
        'handle': player.handle,
        'codecs': codecs,
        'hardwareEnabled': hardwareEnabled,
        'qualityCode': qualityCode,
        'width': width,
        'height': height,
        'directOutput': MpvHdrPolicy.directOutput(
          profile5: profile5,
          hardwareEnabled: hardwareEnabled,
        ),
        'options': MpvHdrPolicy.options(
          profile5: profile5,
          hardwareEnabled: hardwareEnabled,
        ),
      });
      _created = true;
      _sizeSubscription = player.stream.videoParams.listen((params) {
        final width = params.dw;
        final height = params.dh;
        if (width == null || height == null || width <= 0 || height <= 0) {
          return;
        }
        unawaited(_invoke('videoSize', {'width': width, 'height': height}));
      });
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? values]) async {
    if (_released) return;
    await _methods.invokeMethod<void>(method, {
      'sessionId': sessionId,
      ...?values,
    });
  }

  Future<void> setResizeMode(String mode) =>
      _invoke('resizeMode', {'mode': mode});

  Future<void> hideSurface() => _invoke('hide');

  /// 读取 mpv 原生 SurfaceView 的低分辨率当前帧，供状态栏环境背景使用。
  Future<Uint8List?> captureAmbientFrame({
    int width = 96,
    int height = 54,
  }) async {
    if (_released || !_created) return null;
    final value = await _methods.invokeMethod<dynamic>(
      'captureAmbientFrame',
      {
        'sessionId': sessionId,
        'width': width,
        'height': height,
      },
    );
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  Future<AmbientRgbaFrame?> captureAmbientPixels({
    int width = 96,
    int height = 54,
  }) async {
    if (_released || !_created) return null;
    final value = await _methods.invokeMethod<Object?>(
      'captureAmbientFrame',
      {
        'sessionId': sessionId,
        'width': width,
        'height': height,
        'format': 'rgba8888',
      },
    );
    return AmbientRgbaFrame.fromMessage(value);
  }

  Widget buildView({Key? key}) => PlatformViewLink(
    key: key,
    viewType: 'piliexo/mpv_hdr_surface',
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) {
      final controller = PlatformViewsService.initExpensiveAndroidView(
        id: params.id,
        viewType: 'piliexo/mpv_hdr_surface',
        layoutDirection: TextDirection.ltr,
        creationParams: {'sessionId': sessionId},
        creationParamsCodec: const StandardMessageCodec(),
      )..addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
      unawaited(controller.create());
      return controller;
    },
  );

  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    await _sizeSubscription?.cancel();
    await _subscription?.cancel();
    if (_created) {
      // 原生独立客户端和 Surface 必须先于 media-kit 的主实例释放。
      await _methods.invokeMethod<void>('release', {'sessionId': sessionId});
      _created = false;
    }
    await _errors.close();
    diagnostics.dispose();
  }
}
