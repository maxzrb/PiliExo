import 'dart:io' show Platform;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/release_version.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

abstract final class Update {
  static const _androidUpdateChannel = MethodChannel(
    'com.maxzrb.piliexo/update',
  );

  // 检查更新
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (kDebugMode) return;
    SmartDialog.dismiss();
    try {
      final res = await Request().get(
        Api.latestApp,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          extra: {'account': const NoAccount()},
        ),
      );
      final data = _asMap(res.data);
      final latest = ReleaseVersion.tryParse(data?['tag_name']?.toString());
      final current = ReleaseVersion.current;
      if (data == null || latest == null || current == null) {
        if (!isAuto) {
          SmartDialog.showToast('检查更新失败，Release 标签格式不受支持');
        }
        return;
      }

      if (latest.compareTo(current) <= 0) {
        if (!isAuto) {
          SmartDialog.showToast('已是最新版本');
        }
        return;
      }

      SmartDialog.show(
        animationType: SmartAnimationType.centerFade_otherSlide,
        builder: (context) {
          final colorScheme = ColorScheme.of(context);
          Widget downloadBtn(String text, {String? ext}) => TextButton(
            onPressed: () => onDownload(data, ext: ext),
            child: Text(text),
          );
          final tag = latest.tag;
          return AlertDialog(
            title: const Text('🎉 发现新版本'),
            content: SizedBox(
              height: 280,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 8),
                    Text('${data['body'] ?? '暂无更新说明'}'),
                    TextButton(
                      onPressed: () => PageUtils.launchURL(
                        '${Constants.sourceCodeUrl}/releases/tag/${Uri.encodeComponent(tag)}',
                      ),
                      child: Text(
                        '点此查看完整更新内容',
                        style: TextStyle(color: colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (isAuto)
                TextButton(
                  onPressed: () {
                    SmartDialog.dismiss();
                    GStorage.setting.put(SettingBoxKey.autoUpdate, false);
                  },
                  child: Text(
                    '不再提醒',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
              TextButton(
                onPressed: SmartDialog.dismiss,
                child: Text(
                  '取消',
                  style: TextStyle(color: colorScheme.outline),
                ),
              ),
              if (Platform.isWindows) ...[
                downloadBtn('zip', ext: 'zip'),
                downloadBtn('exe', ext: 'exe'),
              ] else if (Platform.isLinux) ...[
                downloadBtn('rpm', ext: 'rpm'),
                downloadBtn('deb', ext: 'deb'),
                downloadBtn('targz', ext: 'tar.gz'),
              ] else if (Platform.isAndroid)
                downloadBtn('下载 Android APK')
              else
                downloadBtn('GitHub'),
            ],
          );
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
    }
  }

  // 下载适用于当前系统的安装包。Android 先探测 ModelScope 镜像，失败后使用 GitHub 资产。
  static Future<void> onDownload(Map data, {String? ext}) async {
    SmartDialog.dismiss();
    try {
      final assets = _assets(data);
      final Map<String, dynamic>? asset;
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        asset = findAndroidAsset(
          assets,
          androidInfo.supportedAbis,
        );
      } else {
        asset = _findAsset(
          assets,
          [Platform.operatingSystem],
          ext: ext,
        );
      }
      if (asset == null) {
        throw UnsupportedError('没有找到适用于当前平台的 Release 资产');
      }

      final assetName = asset['name']?.toString();
      final githubUrl = asset['browser_download_url']?.toString();
      final tag = data['tag_name']?.toString();
      if (Platform.isAndroid && assetName != null && tag != null) {
        final mirrorUrl = _modelScopeAssetUrl(tag, assetName);
        final urls = <String>[
          if (await _isReachable(mirrorUrl)) mirrorUrl,
          if (githubUrl != null && githubUrl.isNotEmpty) githubUrl,
        ];
        if (urls.isNotEmpty) {
          await _downloadAndroidUpdate(
            urls: urls,
            fileName: assetName,
            expectedSha256: _assetSha256(asset),
          );
          return;
        }
        SmartDialog.showToast('没有可用的更新下载地址');
      }

      if (githubUrl != null && githubUrl.isNotEmpty) {
        await PageUtils.launchURL(githubUrl);
        return;
      }
      throw UnsupportedError('Release 资产没有下载地址');
    } catch (e) {
      if (kDebugMode) debugPrint('download error: $e');
      final tag = data['tag_name']?.toString();
      final fallback = tag == null
          ? '${Constants.sourceCodeUrl}/releases/latest'
          : '${Constants.sourceCodeUrl}/releases/tag/${Uri.encodeComponent(tag)}';
      await PageUtils.launchURL(fallback);
    }
  }

  /// Android 优先使用内置 Aria2-next；不支持该架构时回退到单连接 HTTP 下载。
  ///
  /// Aria2-next 完成并校验文件后会直接唤起系统安装器，系统仍会按 Android
  /// 安全策略显示安装确认界面，应用本身不能静默替用户确认安装。
  static Future<void> _downloadAndroidUpdate({
    required List<String> urls,
    required String fileName,
    required String? expectedSha256,
  }) async {
    try {
      SmartDialog.showLoading(msg: '正在下载更新（Aria2-next 32 分片）');
      try {
        await _androidUpdateChannel.invokeMethod<bool>('downloadAndInstall', {
          'urls': urls,
          'fileName': fileName,
          'expectedSha256': expectedSha256,
        });
      } on PlatformException catch (error) {
        if (error.code != 'aria2_unavailable' &&
            error.code != 'download_failed') {
          rethrow;
        }
        // 目前 Aria2-next 官方 Android 发行包提供 ARM64；其它架构仍保持可更新。
        SmartDialog.showLoading(msg: '正在下载更新');
        final savePath = await _androidUpdateChannel.invokeMethod<String>(
          'prepareUpdateFile',
          {'fileName': fileName},
        );
        if (savePath == null || savePath.isEmpty) {
          throw StateError('无法准备更新文件');
        }

        Object? lastError;
        var downloaded = false;
        for (final url in urls) {
          try {
            await Dio().download(
              url,
              savePath,
              deleteOnError: true,
              options: Options(
                headers: {'user-agent': BrowserUa.mob},
                followRedirects: true,
                receiveTimeout: const Duration(minutes: 10),
                sendTimeout: const Duration(minutes: 10),
              ),
            );
            downloaded = true;
            break;
          } catch (error) {
            lastError = error;
          }
        }
        if (!downloaded) {
          throw StateError('更新下载失败：$lastError');
        }
        await _androidUpdateChannel.invokeMethod<bool>('installApk', {
          'path': savePath,
          'expectedSha256': expectedSha256,
        });
      }
      SmartDialog.showToast('更新已下载，正在打开安装程序');
    } finally {
      SmartDialog.dismiss();
    }
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) {
      return null;
    }
    return value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  static List<Map<String, dynamic>> _assets(Map data) {
    final value = data['assets'];
    if (value is! List) {
      return const [];
    }
    return value.map(_asMap).whereType<Map<String, dynamic>>().toList();
  }

  /// 按系统报告的首选 ABI 选择精确 APK；找不到时只允许回退通用 APK。
  ///
  /// 不再把另一个架构的 APK 当作通用包，避免 Android 安装成功后启动崩溃。
  static Map<String, dynamic>? findAndroidAsset(
    List<Map<String, dynamic>> assets,
    Iterable<String> supportedAbis,
  ) {
    for (final abi in supportedAbis) {
      final normalizedAbi = abi.toLowerCase();
      for (final asset in assets) {
        final name = asset['name']?.toString() ?? '';
        if (_androidAbiFromName(name) == normalizedAbi &&
            name.toLowerCase().endsWith('.apk')) {
          return asset;
        }
      }
    }

    for (final asset in assets) {
      final name = asset['name']?.toString() ?? '';
      final normalizedName = name.toLowerCase();
      if (normalizedName.endsWith('.apk') &&
          _androidAbiFromName(name) == null &&
          (normalizedName.contains('universal') ||
              normalizedName.contains('android'))) {
        return asset;
      }
    }
    return null;
  }

  static String? _androidAbiFromName(String name) {
    final normalizedName = name.toLowerCase();
    for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']) {
      if (normalizedName.contains(abi)) {
        return abi;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findAsset(
    List<Map<String, dynamic>> assets,
    Iterable<String> platforms, {
    String? ext,
    String? fallbackExtension,
  }) {
    bool matchesExtension(String name) {
      return ext == null || ext.isEmpty || name.endsWith(ext);
    }

    for (final platform in platforms) {
      final normalizedPlatform = platform.toLowerCase();
      for (final asset in assets) {
        final name = asset['name']?.toString() ?? '';
        if (name.toLowerCase().contains(normalizedPlatform) &&
            matchesExtension(name)) {
          return asset;
        }
      }
    }

    if (fallbackExtension != null) {
      for (final asset in assets) {
        final name = asset['name']?.toString() ?? '';
        if (name.toLowerCase().endsWith(fallbackExtension) &&
            matchesExtension(name)) {
          return asset;
        }
      }
    }
    return null;
  }

  static String _modelScopeAssetUrl(String tag, String assetName) {
    final encodedTag = Uri.encodeComponent(tag);
    final encodedName = assetName.split('/').map(Uri.encodeComponent).join('/');
    return '${Constants.modelScopeReleaseBaseUrl}/$encodedTag/$encodedName';
  }

  static String? _assetSha256(Map<String, dynamic> asset) {
    final digest = asset['digest']?.toString().trim().toLowerCase();
    if (digest == null) return null;
    final normalized = digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : digest;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }

  static Future<bool> _isReachable(String url) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ),
    );
    try {
      final response = await dio.head<void>(
        url,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          followRedirects: true,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 400;
    } catch (_) {
      return false;
    }
  }
}
