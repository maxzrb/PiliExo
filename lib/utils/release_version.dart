import 'package:PiliPlus/build_config.dart';

/// PiliExo 使用 v两位年份.月份.日期.当天构建次数作为发布标签。
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion({
    required this.year,
    required this.month,
    required this.day,
    required this.build,
  });

  static final _pattern = RegExp(
    r'^v(\d{2})\.(\d{1,2})\.(\d{1,2})\.(\d+)$',
  );

  final int year;
  final int month;
  final int day;
  final int build;

  static ReleaseVersion? tryParse(String? tag) {
    if (tag == null) {
      return null;
    }
    final match = _pattern.firstMatch(tag.trim());
    if (match == null) {
      return null;
    }

    final version = ReleaseVersion(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
      build: int.parse(match.group(4)!),
    );
    if (version.month < 1 || version.month > 12 || version.day < 1 || version.day > 31) {
      return null;
    }
    return version;
  }

  static ReleaseVersion? get current {
    final name = BuildConfig.versionName.split('-').first;
    return tryParse('v$name.${BuildConfig.versionCode}');
  }

  String get tag => 'v$year.$month.$day.$build';

  @override
  int compareTo(ReleaseVersion other) {
    final left = [year, month, day, build];
    final right = [other.year, other.month, other.day, other.build];
    for (var i = 0; i < left.length; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) {
        return result;
      }
    }
    return 0;
  }

  @override
  String toString() => tag;
}
