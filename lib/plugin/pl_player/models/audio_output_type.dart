import 'package:PiliPlus/models/common/enum_with_label.dart';

enum AudioOutput implements EnumWithLabel {
  opensles('OpenSL ES'),
  audiotrack('AudioTrack'),
  aaudio('AAudio'),
  ;

  static final defaultValue = values.map((e) => e.name).join(',');

  @override
  final String label;
  const AudioOutput(this.label);
}
