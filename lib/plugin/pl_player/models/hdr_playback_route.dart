/// 三条播放路线互斥；旧版的两个开关只用于首次读取时继承偏好。
enum HdrPlaybackRoute {
  mpvCompatible('mpv-compatible', 'mpv 兼容播放'),
  mpvNative('mpv-native', 'mpv 原生 HDR'),
  media3Native('media3-native', 'Media3 原生 HDR');

  const HdrPlaybackRoute(this.storageValue, this.title);

  final String storageValue;
  final String title;

  bool get isNative => this != mpvCompatible;

  static HdrPlaybackRoute resolve({
    required Object? stored,
    required bool legacyMedia3,
    required bool legacyMpv,
  }) {
    for (final route in values) {
      if (route.storageValue == stored) return route;
    }
    // 旧版两个开关同时打开时，mpv 原生 HDR 的优先级更高。
    return legacyMpv
        ? mpvNative
        : legacyMedia3
        ? media3Native
        : mpvCompatible;
  }

  String get summary => switch (this) {
    mpvCompatible => '兼容性最好，支持超分',
    mpvNative => '保留 mpv 音频与控制，HDR 走原生 Surface',
    media3Native => 'Media3 解码，原生 HDR 显示',
  };

  String get details => switch (this) {
    mpvCompatible => '兼容性最好，支持 Anime4K 等视频超分。HDR 由 mpv 映射为普通画面输出。',
    mpvNative => 'HDR 由原生 Surface 输出，系统负责亮度适配。直出模式不支持 mpv 视频着色器。',
    media3Native =>
      '由 Media3 / ExoPlayer 解码并通过原生 Surface 播放 HDR。杜比视界与 HDR Vivid 需要设备支持。',
  };
}
