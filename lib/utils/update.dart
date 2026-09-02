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
import 'package:flutter/foundation.dart'
    show ValueChanged, debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.downloadedBytes,
    this.totalBytes,
  });

  final int downloadedBytes;
  final int? totalBytes;

  double? get value {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (downloadedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

/// 根据实际尝试的地址生成更新下载状态文案。
String updateDownloadSourceLabel(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host == 'modelscope.cn' || host.endsWith('.modelscope.cn')) {
    return 'ModelScope 镜像源';
  }
  if (host == 'github.com' ||
      host.endsWith('.github.com') ||
      host == 'githubusercontent.com' ||
      host.endsWith('.githubusercontent.com')) {
    return 'GitHub 源';
  }
  return '备用下载源';
}

// 新密钥首次发布时，旧签名版本必须卸载后重新安装；后续版本沿用新密钥即可覆盖更新。
const updateSigningKeyMigrationTag = 'v26.9.2.1';
const updateSigningKeyMigrationNotice =
    '重要：因更换 Android 签名密钥，本版本无法覆盖更新旧版，也无法直接覆盖安装。请先备份应用数据，卸载旧版后再安装；卸载可能清除本地数据。安装本版本后，后续同签名版本可直接覆盖更新。';

String? updateSigningKeyMigrationNoticeFor({
  required String currentTag,
  required String latestTag,
}) {
  final current = ReleaseVersion.tryParse(currentTag);
  final latest = ReleaseVersion.tryParse(latestTag);
  final migration = ReleaseVersion.tryParse(updateSigningKeyMigrationTag);
  if (current == null || latest == null || migration == null) {
    return null;
  }
  if (current.compareTo(migration) < 0 && latest.compareTo(migration) >= 0) {
    return updateSigningKeyMigrationNotice;
  }
  return null;
}

abstract final class Update {
  static const _androidUpdateChannel = MethodChannel(
    'com.maxzrb.piliexo/update',
  );

  static ValueChanged<UpdateDownloadProgress>? _progressListener;
  static CancelToken? _activeCancelToken;
  static bool _progressHandlerInstalled = false;

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
        onDismiss: _cancelActiveDownload,
        builder: (_) => _UpdateDialog(
          data: data,
          tag: latest.tag,
          isAuto: isAuto,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
    }
  }

  // 下载适用于当前系统的安装包。Android 先探测 ModelScope 镜像，失败后使用 GitHub 资产。
  static Future<bool> onDownload(
    Map data, {
    String? ext,
    ValueChanged<UpdateDownloadProgress>? onProgress,
    ValueChanged<String>? onStatus,
  }) async {
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    try {
      onStatus?.call('正在准备更新下载…');
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

      if (cancelToken.isCancelled) {
        throw const _UpdateCancelled();
      }

      final assetName = asset['name']?.toString();
      final githubUrl = asset['browser_download_url']?.toString();
      final tag = data['tag_name']?.toString();
      if (Platform.isAndroid && assetName != null && tag != null) {
        onStatus?.call('正在查找可用下载地址…');
        final mirrorUrl = _modelScopeAssetUrl(tag, assetName);
        final urls = <String>[
          if (await _isReachable(mirrorUrl)) mirrorUrl,
          if (githubUrl != null && githubUrl.isNotEmpty) githubUrl,
        ];
        if (cancelToken.isCancelled) {
          throw const _UpdateCancelled();
        }
        if (urls.isNotEmpty) {
          await _downloadAndroidUpdate(
            urls: urls,
            fileName: assetName,
            expectedSha256: _assetSha256(asset),
            totalBytes: _assetSize(asset),
            cancelToken: cancelToken,
            onProgress: onProgress,
            onStatus: onStatus,
          );
          return true;
        }
        SmartDialog.showToast('没有可用的更新下载地址');
      }

      if (githubUrl != null && githubUrl.isNotEmpty) {
        await PageUtils.launchURL(githubUrl);
        return false;
      }
      throw UnsupportedError('Release 资产没有下载地址');
    } on _UpdateCancelled {
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'download_cancelled') {
        rethrow;
      }
      if (kDebugMode) debugPrint('download error: $e');
      final tag = data['tag_name']?.toString();
      final fallback = tag == null
          ? '${Constants.sourceCodeUrl}/releases/latest'
          : '${Constants.sourceCodeUrl}/releases/tag/${Uri.encodeComponent(tag)}';
      await PageUtils.launchURL(fallback);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('download error: $e');
      final tag = data['tag_name']?.toString();
      final fallback = tag == null
          ? '${Constants.sourceCodeUrl}/releases/latest'
          : '${Constants.sourceCodeUrl}/releases/tag/${Uri.encodeComponent(tag)}';
      await PageUtils.launchURL(fallback);
      return false;
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }
  }

  /// 取消当前更新下载。取消后不会再回退到浏览器下载，也不会安装不完整文件。
  static Future<void> cancelAndroidUpdate() async {
    _activeCancelToken?.cancel('用户取消更新下载');
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidUpdateChannel.invokeMethod<bool>('cancelDownload');
    } on MissingPluginException {
      // 非 Android 或旧版本原生实现没有取消入口时忽略即可。
    }
  }

  static void _cancelActiveDownload() {
    if (_activeCancelToken != null) {
      cancelAndroidUpdate();
    }
  }

  /// Android 优先使用内置 Aria2-next；不支持该架构时回退到应用内备用源下载。
  ///
  /// Aria2-next 完成并校验文件后会直接唤起系统安装器，系统仍会按 Android
  /// 安全策略显示安装确认界面，应用本身不能静默替用户确认安装。
  static Future<void> _downloadAndroidUpdate({
    required List<String> urls,
    required String fileName,
    required String? expectedSha256,
    required int? totalBytes,
    required CancelToken cancelToken,
    ValueChanged<UpdateDownloadProgress>? onProgress,
    ValueChanged<String>? onStatus,
  }) async {
    _ensureProgressHandler();
    _progressListener = onProgress;

    void reportProgress(UpdateDownloadProgress progress) {
      onProgress?.call(progress);
      if ((progress.value ?? 0) >= 1) {
        onStatus?.call('正在校验更新文件并打开安装程序…');
      }
    }

    try {
      onStatus?.call('正在下载更新（Aria2-next 32 分片）');
      reportProgress(
        UpdateDownloadProgress(downloadedBytes: 0, totalBytes: totalBytes),
      );
      if (cancelToken.isCancelled) {
        throw const _UpdateCancelled();
      }
      try {
        await _androidUpdateChannel.invokeMethod<bool>('downloadAndInstall', {
          'urls': urls,
          'fileName': fileName,
          'expectedSha256': expectedSha256,
          'totalBytes': totalBytes,
        });
      } on PlatformException catch (error) {
        if (error.code == 'download_cancelled') {
          throw const _UpdateCancelled();
        }
        if (error.code != 'aria2_unavailable' &&
            error.code != 'download_failed') {
          rethrow;
        }
        // 目前 Aria2-next 官方 Android 发行包提供 ARM64；其它架构仍保持可更新。
        reportProgress(
          UpdateDownloadProgress(downloadedBytes: 0, totalBytes: totalBytes),
        );
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
            if (cancelToken.isCancelled) {
              throw const _UpdateCancelled();
            }
            onStatus?.call('正在使用${updateDownloadSourceLabel(url)}下载');
            await Dio().download(
              url,
              savePath,
              deleteOnError: true,
              cancelToken: cancelToken,
              onReceiveProgress: (received, total) {
                final effectiveTotal = total > 0 ? total : totalBytes;
                reportProgress(
                  UpdateDownloadProgress(
                    downloadedBytes: received,
                    totalBytes: effectiveTotal,
                  ),
                );
              },
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
            if (cancelToken.isCancelled) {
              throw const _UpdateCancelled();
            }
            lastError = error;
          }
        }
        if (!downloaded) {
          throw StateError('更新下载失败：$lastError');
        }
        if (cancelToken.isCancelled) {
          throw const _UpdateCancelled();
        }
        await _androidUpdateChannel.invokeMethod<bool>('installApk', {
          'path': savePath,
          'expectedSha256': expectedSha256,
        });
      }
    } finally {
      if (identical(_progressListener, onProgress)) {
        _progressListener = null;
      }
    }
  }

  static void _ensureProgressHandler() {
    if (_progressHandlerInstalled) {
      return;
    }
    _progressHandlerInstalled = true;
    _androidUpdateChannel.setMethodCallHandler((call) async {
      if (call.method == 'downloadProgress') {
        final args = _asMap(call.arguments);
        final downloadedBytes = _asInt(args?['downloadedBytes']) ?? 0;
        final totalBytes = _asInt(args?['totalBytes']);
        _progressListener?.call(
          UpdateDownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      return null;
    });
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

  static int? _assetSize(Map<String, dynamic> asset) {
    final size = _asInt(asset['size']);
    return size != null && size > 0 ? size : null;
  }

  static int? _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
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

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.data,
    required this.tag,
    required this.isAuto,
  });

  final Map<String, dynamic> data;
  final String tag;
  final bool isAuto;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  bool _isCancelling = false;
  String? _downloadStatus;
  UpdateDownloadProgress _progress = const UpdateDownloadProgress(
    downloadedBytes: 0,
  );

  Future<void> _startDownload({String? ext}) async {
    if (_isDownloading) {
      return;
    }
    setState(() {
      _isDownloading = true;
      _isCancelling = false;
      _downloadStatus = '正在准备更新下载…';
      _progress = const UpdateDownloadProgress(downloadedBytes: 0);
    });

    try {
      final installed = await Update.onDownload(
        widget.data,
        ext: ext,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = progress);
        },
        onStatus: (status) {
          if (!mounted) {
            return;
          }
          setState(() => _downloadStatus = status);
        },
      );
      if (!mounted) {
        return;
      }
      if (installed) {
        SmartDialog.dismiss();
        SmartDialog.showToast('更新已下载，正在打开安装程序');
      } else {
        SmartDialog.dismiss();
      }
    } on _UpdateCancelled {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDownloading = false;
        _isCancelling = false;
        _downloadStatus = '已取消下载';
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('update dialog download error: $error');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isDownloading = false;
        _isCancelling = false;
        _downloadStatus = '下载失败，请重试';
      });
    }
  }

  Future<void> _cancelDownload() async {
    if (!_isDownloading || _isCancelling) {
      return;
    }
    setState(() {
      _isCancelling = true;
      _downloadStatus = '正在取消下载…';
    });
    await Update.cancelAndroidUpdate();
    if (mounted) {
      SmartDialog.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final signingKeyNotice = updateSigningKeyMigrationNoticeFor(
      currentTag: ReleaseVersion.current?.tag ?? '',
      latestTag: widget.tag,
    );
    return AlertDialog(
      title: Text(
        _isDownloading
            ? '正在下载更新'
            : signingKeyNotice == null
            ? '🎉 发现新版本'
            : '⚠️ 发现新版本（无法覆盖更新）',
      ),
      content: SizedBox(
        height: _isDownloading
            ? 320
            : signingKeyNotice == null
            ? 280
            : 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (signingKeyNotice != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                signingKeyNotice,
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(widget.tag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 8),
                    Text('${widget.data['body'] ?? '暂无更新说明'}'),
                    TextButton(
                      onPressed: _isDownloading
                          ? null
                          : () => PageUtils.launchURL(
                              '${Constants.sourceCodeUrl}/releases/tag/${Uri.encodeComponent(widget.tag)}',
                            ),
                      child: Text(
                        '点此查看完整更新内容',
                        style: TextStyle(color: colorScheme.primary),
                      ),
                    ),
                    if (!_isDownloading && _downloadStatus != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _downloadStatus!,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 12),
              Text(_downloadStatus ?? '正在下载更新…'),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                minHeight: 5,
                value: _progress.value,
              ),
              const SizedBox(height: 8),
              Text(_progressLabel),
            ],
          ],
        ),
      ),
      actions: _buildActions(colorScheme),
    );
  }

  List<Widget> _buildActions(ColorScheme colorScheme) {
    if (_isDownloading) {
      return [
        TextButton(
          onPressed: _isCancelling ? null : _cancelDownload,
          child: Text(_isCancelling ? '正在取消' : '取消下载'),
        ),
      ];
    }

    Widget downloadBtn(String text, {String? ext}) => TextButton(
      onPressed: () => _startDownload(ext: ext),
      child: Text(text),
    );

    return [
      if (widget.isAuto)
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
    ];
  }

  String get _progressLabel {
    final downloaded = _formatBytes(_progress.downloadedBytes);
    final total = _progress.totalBytes;
    final value = _progress.value;
    if (total == null || total <= 0 || value == null) {
      return '已下载 $downloaded';
    }
    return '${(value * 100).toStringAsFixed(1)}% · $downloaded / ${_formatBytes(total)}';
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = -1;
  do {
    value /= 1024;
    unitIndex++;
  } while (value >= 1024 && unitIndex < units.length - 1);
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

class _UpdateCancelled implements Exception {
  const _UpdateCancelled();
}
