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
      // 沿用已通过长按 exact 手测包的配置，不在洞察清理时启用候选参数。
      if (output.split(',').first.trim() == 'opensles') ...{
        'audio-buffer': '0.02',
        'opensles-buffer-size-in-ms': '20',
      } else if (output.split(',').first.trim() == 'aaudio') ...{
        'audio-buffer': '0.05',
        'aaudio-performance-mode': 'low-latency',
      },
    },
  };
}
