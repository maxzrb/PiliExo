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

  test('AudioTrack 保留明确选择，未验证成功的调参不进入正式路径', () {
    const output = 'audiotrack,opensles,aaudio';
    final options = MpvAudioOptions.forOutput(
      isAndroid: true,
      output: output,
    );
    expect(options, {
      'ao': output,
      'audio-pitch-correction': 'yes',
    });
  });

  test('AudioTrack手测候选按原生能力适配，不设置全局48k采样率或关闭音调', () {
    final options = MpvAudioOptions.forOutput(
      isAndroid: true,
      output: 'audiotrack,aaudio,opensles',
      audioTrackCandidate: true,
    );
    expect(options, isNot(contains('aaudio-session-id')));
    expect(options, isNot(contains('aaudio-adaptive-session')));
    expect(options['audiotrack-adaptive-rate'], 'yes');
    expect(options['audiotrack-low-latency'], 'yes');
    expect(options['audio-pitch-correction'], 'yes');
    expect(options, isNot(contains('audio-samplerate')));
  });

  test('其他音频输出回退到AudioTrack时也保留Hi-Res，不改变首选输出', () {
    final options = MpvAudioOptions.forOutput(
      isAndroid: true,
      output: 'aaudio,opensles,audiotrack',
      audioTrackCandidate: true,
    );
    expect(options, isNot(contains('aaudio-session-id')));
    expect(options, isNot(contains('aaudio-adaptive-session')));
    expect(options['audiotrack-adaptive-rate'], 'yes');
    expect(options['ao'], 'aaudio,opensles,audiotrack');
    expect(options, isNot(contains('audio-samplerate')));
  });

  test('其他平台不接收 Android 音频驱动参数，倍速仍保持原音调', () {
    expect(
      MpvAudioOptions.forOutput(isAndroid: false, output: 'opensles'),
      {'audio-pitch-correction': 'yes'},
    );
  });
}
