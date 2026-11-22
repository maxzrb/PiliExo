/// 按用户选择的 Android 音频输出配置缓冲，不在切速时重建输出。
abstract final class MpvAudioOptions {
  static Map<String, String> forOutput({
    required bool isAndroid,
    required String output,
  }) => {
    // 倍速始终保留原音调，不用提高音调换取更低延迟。
    'audio-pitch-correction': 'yes',
    if (isAndroid) ...{
      'ao': output,
      if (output.split(',').first.trim() == 'audiotrack')
        // mpv 仍会以实际设备缓冲帧数为下限。
        'audio-buffer': '0.10'
      else if (output.split(',').first.trim() == 'opensles') ...{
        'audio-buffer': '0.02',
        'opensles-buffer-size-in-ms': '20',
      } else if (output.split(',').first.trim() == 'aaudio') ...{
        'audio-buffer': '0.05',
        'aaudio-performance-mode': 'low-latency',
      },
    },
  };
}
