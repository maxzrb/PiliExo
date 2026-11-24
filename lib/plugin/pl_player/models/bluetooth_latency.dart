import 'dart:math' as math;

/// 蓝牙媒体音频协议。区间是设备侧常见延迟，不含手机输出缓冲。
enum BluetoothAudioProtocol {
  none('无', 0, 0),
  a2dp('A2DP', 150, 300),
  hfp('HFP', 100, 250),
  leAudio('LE Audio', 30, 100),
  unknown('未知', 150, 300);

  final String desc;
  final int minMs;
  final int maxMs;

  const BluetoothAudioProtocol(this.desc, this.minMs, this.maxMs);

  static BluetoothAudioProtocol fromValue(Object? value) {
    return switch (value) {
      'a2dp' => a2dp,
      'hfp' => hfp,
      'leAudio' => leAudio,
      'unknown' => unknown,
      _ => none,
    };
  }
}

/// A2DP/LE Audio 编码。Android 用户态不能可靠读取当前协商编码，
/// 因此保留“自动”，其余由用户按耳机实际编码选择。
enum BluetoothAudioCodec {
  auto('自动'),
  sbc('SBC', 190, 210),
  aac('AAC', 140, 160),
  aptX('aptX', 110, 130),
  aptXHd('aptX HD', 120, 140),
  aptXLL('aptX LL', 40, 40),
  ldac('LDAC', 120, 140),
  lhdc('LHDC/HWA', 110, 130),
  l2hc('L2HC', 80, 100),
  lc3('LC3', 30, 100);

  final String desc;
  final int? minMs;
  final int? maxMs;

  const BluetoothAudioCodec(this.desc, [this.minMs, this.maxMs]);

  static BluetoothAudioCodec fromName(String? name) {
    return values.firstWhere(
      (codec) => codec.name == name,
      orElse: () => auto,
    );
  }
}

class BluetoothAudioInfo {
  const BluetoothAudioInfo({
    required this.isBluetooth,
    required this.connected,
    required this.active,
    required this.protocol,
    this.deviceName = '',
    this.refreshRate = 60,
    this.sampleRate = 0,
    this.framesPerBuffer = 0,
  });

  static const none = BluetoothAudioInfo(
    isBluetooth: false,
    connected: false,
    active: false,
    protocol: BluetoothAudioProtocol.none,
  );

  final bool isBluetooth;
  final bool connected;
  final bool active;
  final BluetoothAudioProtocol protocol;
  final String deviceName;
  final double refreshRate;
  final int sampleRate;
  final int framesPerBuffer;

  bool get canCompensate => isBluetooth && connected && active;

  factory BluetoothAudioInfo.fromMap(Map<Object?, Object?> map) {
    final isBluetooth = map['isBluetooth'] == true;
    final connected = isBluetooth && map['connected'] == true;
    return BluetoothAudioInfo(
      isBluetooth: isBluetooth,
      connected: connected,
      active: connected && map['active'] != false,
      protocol: isBluetooth
          ? BluetoothAudioProtocol.fromValue(map['protocol'])
          : BluetoothAudioProtocol.none,
      deviceName: map['deviceName']?.toString() ?? '',
      refreshRate: (map['refreshRate'] as num?)?.toDouble() ?? 60,
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 0,
      framesPerBuffer: (map['framesPerBuffer'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 蓝牙延迟补偿的纯算术层。
///
/// 正延迟表示声音应更晚；蓝牙通常让声音先到不了，所以结果一般为负，
/// 对应 mpv 的负 audio-delay（等价于把画面推迟）。
abstract final class BluetoothLatencyPolicy {
  static const minTrimMs = -250;
  static const maxTrimMs = 250;
  static const minDelayMs = -600;
  static const maxDelayMs = 300;

  static ({int min, int max})? effectiveRange(
    BluetoothAudioInfo info,
    BluetoothAudioCodec codec,
  ) {
    if (!info.isBluetooth || !info.connected) return null;
    if (_codecAppliesTo(info.protocol, codec)) {
      final min = codec.minMs;
      final max = codec.maxMs;
      if (min != null && max != null) return (min: min, max: max);
    }
    final protocol = info.protocol == BluetoothAudioProtocol.none
        ? BluetoothAudioProtocol.unknown
        : info.protocol;
    if (protocol.minMs <= 0 || protocol.maxMs <= 0) return null;
    return (min: protocol.minMs, max: protocol.maxMs);
  }

  static bool _codecAppliesTo(
    BluetoothAudioProtocol protocol,
    BluetoothAudioCodec codec,
  ) {
    if (codec == BluetoothAudioCodec.auto) return false;
    return switch (protocol) {
      BluetoothAudioProtocol.a2dp => codec != BluetoothAudioCodec.lc3,
      BluetoothAudioProtocol.leAudio => codec == BluetoothAudioCodec.lc3,
      BluetoothAudioProtocol.unknown => true,
      _ => false,
    };
  }

  /// 两个刷新周期用于合成/扫描，再加 5ms 调度余量。
  static double displayLatencyMs(double refreshRate) {
    final hz = refreshRate >= 24 && refreshRate <= 500 ? refreshRate : 60.0;
    return (2.0 * 1000.0 / hz + 5.0).clamp(10.0, 100.0);
  }

  /// 手机音频混音/端点缓冲。Android 能给出采样率和每缓冲帧数，
  /// 不把它误当成蓝牙编码延迟。
  static double hostOverheadMs(BluetoothAudioInfo info) {
    if (info.sampleRate <= 0 || info.framesPerBuffer <= 0) return 0;
    return (info.framesPerBuffer * 1000.0 / info.sampleRate).clamp(0.0, 20.0);
  }

  /// 返回应下发的音频时间线偏移；正值声音更晚，负值画面更晚。
  static int computeDelayMs({
    required bool enabled,
    required BluetoothAudioInfo? info,
    required BluetoothAudioCodec codec,
    required int trimMs,
  }) {
    if (!enabled || info == null || !info.canCompensate) return 0;
    final range = effectiveRange(info, codec);
    if (range == null) return 0;
    final bluetoothMs = (range.min + range.max) / 2.0 + hostOverheadMs(info);
    final displayMs = displayLatencyMs(info.refreshRate);
    final trim = trimMs.clamp(minTrimMs, maxTrimMs);
    final delay = (displayMs - bluetoothMs - trim).round();
    return delay.clamp(minDelayMs, maxDelayMs);
  }

  /// Media3 原生视频只能推迟画面，不能把画面提前。
  static int videoDelayMs(int signedDelayMs) => math.max(0, -signedDelayMs);

  static String formatSignedMs(int value) =>
      '${value >= 0 ? '+' : ''}$value ms';
}
