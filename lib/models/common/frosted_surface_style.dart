import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 顶栏、底栏使用的磨砂强度和透明度组合。
enum FrostedSurfaceStyle with EnumWithLabel {
  light('轻薄', blurSigma: 10, surfaceOpacity: 0.64),
  standard('标准', blurSigma: 18, surfaceOpacity: 0.72),
  strong('浓厚', blurSigma: 28, surfaceOpacity: 0.82),
  ;

  @override
  final String label;
  final double blurSigma;
  final double surfaceOpacity;

  const FrostedSurfaceStyle(
    this.label, {
    required this.blurSigma,
    required this.surfaceOpacity,
  });
}
