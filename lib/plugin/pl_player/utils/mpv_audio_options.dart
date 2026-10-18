/// 按用户选择的 Android 音频输出配置缓冲，不在切速时重建输出。
abstract final class MpvAudioOptions {
  static Map<String, String> forOutput({
    required bool isAndroid,
    required String output,
    bool audioTrackCandidate = false,
  }) => {
    // 倍速始终保留原音调，不用提高音调换取更低延迟。
    'audio-pitch-correction': 'yes',
    if (isAndroid) ...{
      'ao': output,
      // 即使由其他输出回退到 AudioTrack，也应保留高采样率请求。
      if (audioTrackCandidate) 'audiotrack-adaptive-rate': 'yes',
      // 顺序由用户设置决定；不能把 AudioTrack 的选择悄悄换成其他输出。
      if (audioTrackCandidate &&
          output.split(',').first.trim() == 'audiotrack') ...{
        'audio-buffer': '0.02',
        'audiotrack-low-latency': 'yes',
        'audiotrack-buffer-ms': '20',
        'audiotrack-chunk-ms': '10',
      } else if (output.split(',').first.trim() == 'opensles') ...{
        'audio-buffer': '0.02',
        'opensles-buffer-size-in-ms': '20',
      } else if (output.split(',').first.trim() == 'aaudio') ...{
        'audio-buffer': '0.05',
        'aaudio-performance-mode': 'low-latency',
      },
    },
  };
}
