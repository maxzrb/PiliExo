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

  group('更新下载源状态', () {
    test('ModelScope 地址显示镜像源', () {
      expect(
        updateDownloadSourceLabel(
          'https://modelscope.cn/datasets/AerithDream/PiliExo/resolve/master/app.apk',
        ),
        'ModelScope 镜像源',
      );
    });

    test('GitHub 地址显示 GitHub 源', () {
      expect(
        updateDownloadSourceLabel(
          'https://github.com/maxzrb/PiliExo/releases/download/v1/app.apk',
        ),
        'GitHub 源',
      );
      expect(
        updateDownloadSourceLabel(
          'https://release-assets.githubusercontent.com/app.apk',
        ),
        'GitHub 源',
      );
    });

    test('未知地址显示备用下载源', () {
      expect(
        updateDownloadSourceLabel('https://example.com/app.apk'),
        '备用下载源',
      );
    });
  });

  group('签名迁移更新提示', () {
    test('旧签名版本升级到新密钥首个版本时提示卸载重装', () {
      final notice = updateSigningKeyMigrationNoticeFor(
        currentTag: 'v26.9.1.1',
        latestTag: 'v26.9.2.1',
      );

      expect(notice, contains('更换 Android 签名密钥'));
      expect(notice, contains('无法覆盖更新'));
      expect(notice, contains('卸载旧版'));
    });

    test('旧版本直接升级到后续新密钥版本也提示迁移', () {
      expect(
        updateSigningKeyMigrationNoticeFor(
          currentTag: 'v26.9.1.1',
          latestTag: 'v26.9.3.1',
        ),
        isNotNull,
      );
    });

    test('新密钥版本不重复提示卸载重装', () {
      expect(
        updateSigningKeyMigrationNoticeFor(
          currentTag: 'v26.9.2.1',
          latestTag: 'v26.9.3.1',
        ),
        isNull,
      );
    });

    test('迁移前版本升级不提示签名迁移', () {
      expect(
        updateSigningKeyMigrationNoticeFor(
          currentTag: 'v26.9.1.1',
          latestTag: 'v26.9.1.2',
        ),
        isNull,
      );
    });
  });
}
