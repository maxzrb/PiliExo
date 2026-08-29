import 'package:PiliPlus/utils/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Release 资产选择', () {
    test('优先选择设备首选 ABI', () {
      final asset = Update.findAndroidAsset(
        [
          {'name': 'PiliExo_android_v26.8.28.2_armeabi-v7a.apk'},
          {'name': 'PiliExo_android_v26.8.28.2_arm64-v8a.apk'},
        ],
        ['arm64-v8a', 'armeabi-v7a'],
      );

      expect(asset?['name'], contains('arm64-v8a'));
    });

    test('首选 ABI 不存在时选择通用 APK', () {
      final asset = Update.findAndroidAsset(
        [
          {'name': 'PiliExo_android_v26.8.28.2_arm64-v8a.apk'},
          {'name': 'PiliExo_android_v26.8.28.2_universal.apk'},
        ],
        ['x86_64'],
      );

      expect(asset?['name'], endsWith('universal.apk'));
    });

    test('没有匹配 ABI 或通用 APK 时不返回错误架构', () {
      final asset = Update.findAndroidAsset(
        [
          {'name': 'PiliExo_android_v26.8.28.2_arm64-v8a.apk'},
        ],
        ['x86_64'],
      );

      expect(asset, isNull);
    });
  });

  group('更新下载进度', () {
    test('按总大小计算进度并限制在 0 到 1', () {
      expect(
        const UpdateDownloadProgress(
          downloadedBytes: 50,
          totalBytes: 100,
        ).value,
        0.5,
      );
      expect(
        const UpdateDownloadProgress(
          downloadedBytes: 150,
          totalBytes: 100,
        ).value,
        1,
      );
    });

    test('没有总大小时使用不确定进度', () {
      expect(
        const UpdateDownloadProgress(downloadedBytes: 50).value,
        isNull,
      );
    });
  });
}
