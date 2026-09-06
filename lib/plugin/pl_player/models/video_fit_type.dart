import 'package:PiliPlus/common/style.dart';
import 'package:material_ui/material_ui.dart' show BoxFit;

enum VideoFitType {
  fill('拉伸', boxFit: BoxFit.fill),
  contain('自动', boxFit: BoxFit.contain),
  cover('裁剪', boxFit: BoxFit.cover),
  fitWidth('等宽', boxFit: BoxFit.fitWidth),
  fitHeight('等高', boxFit: BoxFit.fitHeight),
  none('原始', boxFit: BoxFit.none),
  scaleDown('限制', boxFit: BoxFit.scaleDown),
  ratio_4x3('4:3', aspectRatio: 4 / 3),
  ratio_16x9('16:9', aspectRatio: Style.aspectRatio16x9),
  ;

  final String desc;
  final BoxFit boxFit;
  final double? aspectRatio;
  const VideoFitType(
    this.desc, {
    this.boxFit = BoxFit.contain,
    this.aspectRatio,
  });

  /// Media3 原生播放器支持的画面模式名称。
  ///
  /// `none`、`scaleDown` 和固定比例模式是 Flutter 外层布局的能力；HDR
  /// 固定比例视口使用 `fill` 填满原生视图，确保视频内容实际改变显示比例。
  String get hdrResizeMode => switch (this) {
    .fill => 'fill',
    .cover => 'cover',
    .fitWidth => 'fitWidth',
    .fitHeight => 'fitHeight',
    .ratio_4x3 => 'fill',
    .ratio_16x9 => 'fill',
    _ => 'fit',
  };
}
