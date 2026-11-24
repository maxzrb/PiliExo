import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/models/bluetooth_latency.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// 读取 Android 当前蓝牙输出并把补偿量同步到 mpv / Media3。
class BluetoothLatencyService extends ChangeNotifier
    with WidgetsBindingObserver {
  BluetoothLatencyService._();

  static final instance = BluetoothLatencyService._();
  static const _channel = MethodChannel(
    'com.maxzrb.piliexo/bluetooth_latency',
  );
  static const _calibrationChannel = EventChannel(
    'com.maxzrb.piliexo/bluetooth_latency/calibration',
  );
  static const _monitorInterval = Duration(seconds: 2);

  final ValueNotifier<BluetoothAudioInfo?> info = ValueNotifier(null);
  final ValueNotifier<int> signedDelayMs = ValueNotifier(0);

  Future<void>? _refreshing;
  Timer? _monitor;
  bool _observerAdded = false;
  bool _appResumed = true;

  bool get hasBluetoothOutput => info.value?.canCompensate ?? false;
  bool get isCompensationActive =>
      hasBluetoothOutput && Pref.bluetoothLatencyCompensation;

  BluetoothAudioCodec get codec =>
      BluetoothAudioCodec.fromName(Pref.bluetoothLatencyCodec);

  int get trimMs => Pref.bluetoothLatencyTrimMs;

  int get videoDelayMs =>
      BluetoothLatencyPolicy.videoDelayMs(signedDelayMs.value);

  String get mpvAudioDelaySeconds =>
      (signedDelayMs.value / 1000).toStringAsFixed(3);

  String get statusText {
    if (!Platform.isAndroid) return '仅 Android 蓝牙输出可用';
    final current = info.value;
    if (current == null) return '尚未检测';
    if (!current.isBluetooth || !current.connected) {
      return '当前未检测到蓝牙音频输出';
    }
    final name = current.deviceName.trim().isEmpty
        ? '蓝牙设备'
        : current.deviceName.trim();
    final active = current.active ? '' : '（未确认正在输出）';
    return '$name · ${current.protocol.desc}$active';
  }

  String get summaryText => '$statusText；预计画面延后 $videoDelayMs ms';

  Future<void> refreshAndApply() async {
    await _refreshing;
    return _refreshing ??= _refreshAndApply().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshAndApply() async {
    _ensureObserver();
    var current = BluetoothAudioInfo.none;
    if (Platform.isAndroid) {
      try {
        final map = await _channel.invokeMapMethod<Object?, Object?>(
          'getOutputInfo',
        );
        if (map != null) current = BluetoothAudioInfo.fromMap(map);
      } on MissingPluginException {
        // 单元测试或未注册插件的宿主直接按无蓝牙处理。
      } catch (_) {
        // 音频设备切换瞬间失败时不打断播放。
      }
    }

    final enabled = Pref.bluetoothLatencyCompensation;
    final delay = BluetoothLatencyPolicy.computeDelayMs(
      enabled: enabled,
      info: current,
      codec: codec,
      trimMs: trimMs,
    );
    final nextVideoDelay = BluetoothLatencyPolicy.videoDelayMs(delay);

    info.value = current;
    if (signedDelayMs.value != delay) {
      signedDelayMs.value = delay;
    }

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>(
          'setVideoDelayMs',
          nextVideoDelay,
        );
      } catch (_) {
        // 插件尚未注册或旧宿主不支持时，mpv 路线仍可独立工作。
      }
    }

    _syncMonitor(enabled);
    notifyListeners();
  }

  Stream<int> calibrationCues() =>
      _calibrationChannel.receiveBroadcastStream().cast<int>();

  /// 把当前时间线偏移同步给 mpv；无播放器时安全忽略。
  void applyToMpv(Player? player) {
    if (player == null) return;
    try {
      player.setProperty('audio-delay', mpvAudioDelaySeconds);
    } catch (_) {}
  }

  void _syncMonitor(bool enabled) {
    if (!enabled || !Platform.isAndroid || !_appResumed) {
      _monitor?.cancel();
      _monitor = null;
      return;
    }
    _monitor ??= Timer.periodic(
      _monitorInterval,
      (_) => unawaited(refreshAndApply()),
    );
  }

  void _ensureObserver() {
    if (_observerAdded) return;
    _observerAdded = true;
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'outputChanged') return;
        await refreshAndApply();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) {
      unawaited(refreshAndApply());
    } else {
      _monitor?.cancel();
      _monitor = null;
    }
  }
}
