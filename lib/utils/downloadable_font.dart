import 'dart:io';
import 'dart:ui' show loadFontFromList;

import 'package:PiliPlus/utils/path_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

enum DownloadableFont {
  harmonyOs(
    family: 'HarmonyOS Sans SC',
    source: '华为',
    directory: 'harmonyos-sans-2.400',
    url: 'https://developer.huawei.com/images/download/next/HarmonyOS-Sans.zip',
    license: 'https://developer.huawei.com/consumer/cn/doc/design-guides/font-0000001828772001/',
    files: [
      _FontFile(
        'Regular.ttf',
        8483132,
        'd0828775b6ab60cc677299d678ab848adf62b768f270d23bf3e41e29d987cf6b',
        start: 6855920,
        compressedBytes: 5667691,
      ),
      _FontFile(
        'Medium.ttf',
        8449140,
        '412760db7a5f47c3133f7fd74694b79a1f72de33e28b922a1f540aeecb6fe714',
        start: 12523996,
        compressedBytes: 5706551,
      ),
      _FontFile(
        'Bold.ttf',
        8379892,
        'fa6e8d2a8994427d3ad565951e6101784f9c1af2b9f992ca33be377a201937fe',
        start: 23932612,
        compressedBytes: 5706961,
      ),
    ],
  ),
  miSans(
    family: 'MiSans',
    source: '小米',
    directory: 'misans-vf',
    url: 'https://hyperos.mi.com/font-download/MiSans.zip',
    license: 'https://hyperos.mi.com/font/download',
    files: [
      _FontFile(
        'MiSansVF.ttf',
        20093424,
        '4edeacb9ec0015aa67e4d48376b7615f642655ce8e01e5cdff1fec60ddd1ca91',
        start: 213458546,
        compressedBytes: 14410630,
      ),
    ],
  );

  const DownloadableFont({
    required this.family,
    required this.source,
    required String directory,
    required this._url,
    required this.license,
    required this._files,
  }) : _cacheName = directory;

  final String family;
  final String source;
  final String license;
  final String _cacheName;
  final String _url;
  final List<_FontFile> _files;

  // 已加载字形留在引擎内，删掉磁盘缓存后仍可用同版本文件重新安装。
  static final _loaded = <DownloadableFont>{};
  Directory get _directory =>
      Directory(path.join(appSupportDirPath, _cacheName));
  bool get isInstalled => _directory.existsSync();
  String get downloadSize {
    final bytes = _files.fold(0, (total, file) => total + file.compressedBytes);
    return '${(bytes / 1e6).toStringAsFixed(1)} MB';
  }

  Future<void> install() async {
    if (!isInstalled) {
      final staging = await Directory(appSupportDirPath).createTemp('font-');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final uri = Uri.parse(_url);
        for (final file in _files) {
          final bytes = await file.download(client, uri);
          await File(path.join(staging.path, file.name)).writeAsBytes(bytes);
        }
        await staging.rename(_directory.path);
      } finally {
        client.close(force: true);
        if (staging.existsSync()) await staging.delete(recursive: true);
      }
    }
    await loadCached();
  }

  Future<void> remove() async {
    if (isInstalled) await _directory.delete(recursive: true);
  }

  Future<void> loadCached() async {
    if (_loaded.contains(this)) return;
    for (final file in _files) {
      final bytes = await File(path.join(_directory.path, file.name))
          .readAsBytes();
      await loadFontFromList(bytes, fontFamily: family);
    }
    _loaded.add(this);
  }
}

class _FontFile {
  const _FontFile(
    this.name,
    this.size,
    this.digest, {
    required this.start,
    required this.compressedBytes,
  });

  final String name;
  final int size;
  final String digest;
  // 官方 ZIP 中原始 Deflate 数据的起点和长度。
  final int start;
  final int compressedBytes;

  Future<List<int>> download(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=$start-${start + compressedBytes - 1}',
    );
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.partialContent) {
      throw FormatException('字体下载失败（HTTP ${response.statusCode}）');
    }
    final bytes = await consolidateHttpClientResponseBytes(
      response,
      onBytesReceived: (received, _) {
        if (received > compressedBytes) {
          throw const FormatException('字体下载过大');
        }
      },
    ).timeout(const Duration(minutes: 2));
    if (bytes.length != compressedBytes) {
      throw const FormatException('字体下载大小不匹配');
    }
    return compute(_verify, bytes);
  }

  List<int> _verify(Uint8List bytes) {
    if (sha256.convert(bytes).toString() != digest) {
      throw const FormatException('字体校验失败');
    }
    final font = ZLibDecoder(raw: true).convert(bytes);
    if (font.length != size) throw const FormatException('字体大小不匹配');
    return font;
  }
}
