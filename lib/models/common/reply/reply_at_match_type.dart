import 'package:PiliPlus/models/common/enum_with_label.dart';

enum ReplyAtBlockType implements EnumWithLabel {
  disable(-2, '禁用'),
  count(0, '按数量'),
  atOnly(-1, '只包含@'),
  ;

  final int value;
  @override
  final String label;

  const ReplyAtBlockType(this.value, this.label);
}
