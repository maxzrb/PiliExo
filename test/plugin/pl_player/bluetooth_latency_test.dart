import 'package:PiliPlus/plugin/pl_player/models/bluetooth_latency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a2dp = BluetoothAudioInfo(
    isBluetooth: true,
    connected: true,
    active: true,
    protocol: BluetoothAudioProtocol.a2dp,
    refreshRate: 60,
  );
  const leAudio = BluetoothAudioInfo(
    isBluetooth: true,
    connected: true,
    active: true,
    protocol: BluetoothAudioProtocol.leAudio,
    refreshRate: 60,
  );
  const highRefreshA2dp = BluetoothAudioInfo(
    isBluetooth: true,
    connected: true,
    active: true,
    protocol: BluetoothAudioProtocol.a2dp,
    refreshRate: 144,
  );

  int delay(
    BluetoothAudioInfo? info, {
    BluetoothAudioCodec codec = BluetoothAudioCodec.auto,
    int trimMs = 0,
    bool enabled = true,
  }) => BluetoothLatencyPolicy.computeDelayMs(
    enabled: enabled,
    info: info,
    codec: codec,
    trimMs: trimMs,
  );

  group('蓝牙延迟策略', () {
    test('关闭、非蓝牙或未确认输出时不下发偏移', () {
      expect(delay(a2dp, enabled: false), 0);
      expect(delay(BluetoothAudioInfo.none), 0);
      expect(
        delay(
          const BluetoothAudioInfo(
            isBluetooth: true,
            connected: false,
            active: false,
            protocol: BluetoothAudioProtocol.a2dp,
          ),
        ),
        0,
      );
      expect(
        delay(
          const BluetoothAudioInfo(
            isBluetooth: true,
            connected: true,
            active: false,
            protocol: BluetoothAudioProtocol.a2dp,
          ),
        ),
        0,
      );
    });

    test('A2DP 自动区间和刷新率换算', () {
      expect(delay(a2dp), -187);
      expect(delay(highRefreshA2dp), -206);
    });

    test('额外补偿在自动估值上叠加，范围为 ±250ms', () {
      expect(delay(a2dp, trimMs: 20), -207);
      expect(delay(a2dp, trimMs: 100), -287);
      expect(delay(a2dp, trimMs: 200), -387);
      expect(delay(a2dp, trimMs: 300), -437);
      expect(delay(a2dp, trimMs: -200), 13);
      expect(delay(a2dp, trimMs: -250), 63);
      expect(delay(a2dp, trimMs: -300), 63);
    });

    test('手动编码覆盖 A2DP 区间', () {
      expect(delay(a2dp, codec: BluetoothAudioCodec.aac), -112);
      expect(delay(a2dp, codec: BluetoothAudioCodec.aptX), -82);
      expect(
        delay(a2dp, codec: BluetoothAudioCodec.aptXLL),
        -2,
      );
      expect(delay(a2dp, codec: BluetoothAudioCodec.aptXLL, trimMs: -250), 248);
      expect(delay(a2dp, codec: BluetoothAudioCodec.ldac), -92);
      expect(delay(a2dp, codec: BluetoothAudioCodec.lc3), -187);
    });

    test('LE Audio 只接受 LC3，HFP 忽略 A2DP 编码', () {
      expect(delay(leAudio, codec: BluetoothAudioCodec.lc3), -27);
      expect(delay(leAudio, codec: BluetoothAudioCodec.aac), -27);
      const hfp = BluetoothAudioInfo(
        isBluetooth: true,
        connected: true,
        active: true,
        protocol: BluetoothAudioProtocol.hfp,
        refreshRate: 60,
      );
      expect(delay(hfp, codec: BluetoothAudioCodec.aac), -137);
    });

    test('未知协议回退 A2DP 区间，但仍可使用手动编码', () {
      const unknown = BluetoothAudioInfo(
        isBluetooth: true,
        connected: true,
        active: true,
        protocol: BluetoothAudioProtocol.unknown,
        refreshRate: 60,
      );
      expect(delay(unknown), -187);
      expect(delay(unknown, codec: BluetoothAudioCodec.aac), -112);
    });

    test('音频缓冲计入蓝牙侧延迟', () {
      const buffered = BluetoothAudioInfo(
        isBluetooth: true,
        connected: true,
        active: true,
        protocol: BluetoothAudioProtocol.a2dp,
        refreshRate: 60,
        sampleRate: 48000,
        framesPerBuffer: 192,
      );
      expect(delay(buffered), -191);
    });

    test('屏幕延迟合法范围和边界', () {
      expect(
        BluetoothLatencyPolicy.displayLatencyMs(24),
        closeTo(88.3333, 0.001),
      );
      expect(
        BluetoothLatencyPolicy.displayLatencyMs(60),
        closeTo(38.3333, 0.001),
      );
      expect(
        BluetoothLatencyPolicy.displayLatencyMs(144),
        closeTo(18.8889, 0.001),
      );
      expect(
        BluetoothLatencyPolicy.displayLatencyMs(0),
        closeTo(38.3333, 0.001),
      );
      expect(
        BluetoothLatencyPolicy.displayLatencyMs(1000),
        closeTo(38.3333, 0.001),
      );
    });

    test('Media3 只接受非负画面延迟', () {
      expect(BluetoothLatencyPolicy.videoDelayMs(-187), 187);
      expect(BluetoothLatencyPolicy.videoDelayMs(0), 0);
      expect(BluetoothLatencyPolicy.videoDelayMs(20), 0);
    });

    test('原生输出信息解析', () {
      final info = BluetoothAudioInfo.fromMap({
        'isBluetooth': true,
        'connected': true,
        'active': true,
        'protocol': 'leAudio',
        'deviceName': '测试耳机',
        'refreshRate': 120.0,
        'sampleRate': 48000,
        'framesPerBuffer': 192,
      });
      expect(info.isBluetooth, true);
      expect(info.canCompensate, true);
      expect(info.protocol, BluetoothAudioProtocol.leAudio);
      expect(info.deviceName, '测试耳机');
      expect(info.refreshRate, 120);
      expect(info.sampleRate, 48000);
      expect(info.framesPerBuffer, 192);
    });
  });
}
