import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/utils/release_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReleaseVersion', () {
    test('解析 PiliExo 发布标签', () {
      final version = ReleaseVersion.tryParse('v26.8.28.1');

      expect(version?.tag, 'v26.8.28.1');
      expect(version?.year, 26);
      expect(version?.build, 1);
    });

    test('拒绝非四段日期标签', () {
      expect(ReleaseVersion.tryParse('v2.1.2'), isNull);
      expect(ReleaseVersion.tryParse('v26.13.1.1'), isNull);
      expect(ReleaseVersion.tryParse('v26.8.32.1'), isNull);
    });

    test('按日期和当天构建次数比较', () {
      final first = ReleaseVersion.tryParse('v26.8.28.1')!;
      final second = ReleaseVersion.tryParse('v26.8.28.2')!;
      final nextDay = ReleaseVersion.tryParse('v26.8.29.1')!;

      expect(first.compareTo(second), lessThan(0));
      expect(second.compareTo(nextDay), lessThan(0));
    });

    test('发布序号不使用 Android versionCode', () {
      final version = ReleaseVersion.fromBuildMetadata(
        versionName: '26.8.30',
        releaseBuild: 1,
      );

      expect(version?.tag, 'v26.8.30.1');
      expect(BuildConfig.versionCode, isNot(BuildConfig.releaseBuild));
      expect(ReleaseVersion.current?.build, BuildConfig.releaseBuild);
    });
  });
}
