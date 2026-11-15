/// 原生 mpv HDR 的选项集中在这里，便于用固定输入和参考输出核验。
abstract final class MpvHdrPolicy {
  // 仅本机构建的固定样例核验使用；正式构建为空，编译器会移除该分支。
  static const fateInput = String.fromEnvironment('PILIEXO_MPV_HDR_FATE_INPUT');
  // Android 合成器负责适配面板亮度；这里保留完整 PQ 信号范围，避免重复压缩。
  // HLG 由配套核心保留原传递函数及 1000 nit 参考条件，不套用 PQ 的范围。
  static const targetPeak = String.fromEnvironment(
    'PILIEXO_MPV_HDR_TARGET_PEAK',
    defaultValue: '10000',
  );

  static int? dolbyVisionProfile(String? codecs) {
    final match = RegExp(
      r'^(?:dvh1|dvhe)\.(\d{1,2})\.',
      caseSensitive: false,
    ).firstMatch(codecs?.trim() ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool needsProfile5Correction(String? codecs) =>
      dolbyVisionProfile(codecs) == 5;

  static String decoderType(String? current) => switch (current) {
    null || '' => '',
    'no' => '软解',
    _ => '硬解',
  };

  static bool directOutput({
    required bool profile5,
    required bool hardwareEnabled,
  }) => hardwareEnabled && !profile5;

  static Map<String, String> options({
    required bool profile5,
    bool hardwareEnabled = true,
  }) => {
    'vo': 'null',
    'vid': 'auto',
    'gpu-api': 'opengl',
    'gpu-context': 'android',
    'opengl-es': 'yes',
    // 配套核心按实际输出选择 PQ/HLG EGLSurface，并提交可用的 HDR10 静态元数据。
    'android-hdr-signal-passthrough': 'yes',
    'egl-output-format': 'rgb10_a2',
    'target-prim': 'bt.2020',
    'target-trc': 'pq',
    // Android/EGL 尚无上游协商实现，目标像素和原生 dataspace 由本路径成对设置。
    'target-colorspace-hint': 'no',
    'dither-depth': '10',
    'video-output-levels': 'full',
    'target-peak': targetPeak,
    'tone-mapping': 'clip',
    'gamut-mapping-mode': 'clip',
    'hdr-compute-peak': 'no',
    'inverse-tone-mapping': 'no',
    'hdr-contrast-recovery': '0',
    if (fateInput.isNotEmpty) 'loop-file': 'inf',
    // 原生硬解直出需要 MediaCodec Surface；P5 或用户关闭硬解时交给软件解析 RPU。
    'hwdec': directOutput(profile5: profile5, hardwareEnabled: hardwareEnabled)
        ? 'mediacodec'
        : 'no',
  };
}
