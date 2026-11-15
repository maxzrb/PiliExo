import 'package:PiliPlus/plugin/pl_player/utils/mpv_audio_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenSL 缓冲在初始化时设置，并保留用户的回退顺序和原音调', () {
    const output = 'opensles,aaudio,audiotrack';
    final options = MpvAudioOptions.forOutput(
      isAndroid: true,
      output: output,
    );
    expect(options['ao'], output);
    expect(options['audio-buffer'], '0.02');
    expect(options['opensles-buffer-size-in-ms'], '20');
    expect(options['audio-pitch-correction'], 'yes');
    expect(options, isNot(contains('af')));
  });

  test('AAudio 使用已对照的低延迟模式，不强制更小的驱动容量', () {
    final options = MpvAudioOptions.forOutput(
      isAndroid: true,
      output: 'aaudio,opensles,audiotrack',
    );
    expect(options['audio-buffer'], '0.05');
    expect(options['aaudio-performance-mode'], 'low-latency');
    expect(options, isNot(contains('aaudio-buffer-capacity')));
    expect(options, isNot(contains('aaudio-session-id')));
    expect(options, isNot(contains('aaudio-adaptive-session')));
    expect(options, isNot(contains('af')));
    expect(options['audio-pitch-correction'], 'yes');
  });

  test('AudioTrack与已通过exact手测的包一致，不额外启用原生候选参数', () {
    const output = 'audiotrack,aaudio,opensles';
    expect(MpvAudioOptions.forOutput(isAndroid: true, output: output), {
      'audio-pitch-correction': 'yes',
      'ao': output,
    });
  });

  test('AAudio回退顺序与已通过手测包一致，不附加AudioTrack候选参数', () {
    const output = 'aaudio,opensles,audiotrack';
    expect(MpvAudioOptions.forOutput(isAndroid: true, output: output), {
      'audio-pitch-correction': 'yes',
      'ao': output,
      'audio-buffer': '0.05',
      'aaudio-performance-mode': 'low-latency',
    });
  });

  test('其他平台不接收 Android 音频驱动参数，倍速仍保持原音调', () {
    expect(
      MpvAudioOptions.forOutput(isAndroid: false, output: 'opensles'),
      {'audio-pitch-correction': 'yes'},
    );
  });
}
