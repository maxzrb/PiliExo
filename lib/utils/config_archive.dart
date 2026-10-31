import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/my_reply/view.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/search/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/reply_filter_preferences.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/parse_int.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:archive/archive.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class ImportResult {
  const ImportResult({required this.applied, this.message});

  /// 是否已执行（false 表示取消）
  final bool applied;

  /// 附加提示，无则为 null
  final String? message;
}

abstract final class ConfigArchive {
  static const String metaFileName = 'meta.json';
  static const String settingFileName = 'setting.json';
  static const String accountFileName = 'account.json';
  static const String blacklistFileName = 'blacklist.json';
  static const String replyFileName = 'reply.json';
  static const String searchFileName = 'search.json';
  static const String fontFileName = FontUtils.kFontName;

  static const String _type = 'data_archive';

  /// 归档格式版本
  static const int _majorVersion = 0x0001;
  static const int _minorVersion = 0x0000;

  /// 搜索历史的存储 key
  static const String _searchCacheKey = 'cacheList';

  /// 解压后总大小上限
  static const int _maxTotalBytes = 64 * 1024 * 1024;

  static void export(OutputStream stream) {
    final zip = ZipEncoder()
      ..startEncode(stream)
      ..add(ArchiveFile.string(settingFileName, GStorage.exportAllSettings()))
      ..add(ArchiveFile.string(accountFileName, _exportAccount()))
      ..add(ArchiveFile.string(blacklistFileName, _exportBlacklist()));

    final reply = _exportReply();
    if (reply != null) {
      zip.add(ArchiveFile.string(replyFileName, reply));
    }

    if (FontUtils.fontFile.existsSync()) {
      zip.add(
        ArchiveFile.stream(
          fontFileName,
          InputFileStream(FontUtils.fontFile.path),
        ),
      );
    }

    zip
      ..add(ArchiveFile.string(searchFileName, _exportSearch()))
      ..add(ArchiveFile.string(metaFileName, _buildMeta()))
      ..endEncode();
    return;
  }

  static Future<String?> import(
    Uint8List bytes, {
    required Future<bool> Function(String warning) onWarning,
  }) async {
    if (bytes.length > _maxTotalBytes) {
      throw UnsupportedError('数据包过大');
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    var declaredSize = 0;
    for (final file in archive) {
      declaredSize += file.size;
      if (declaredSize > _maxTotalBytes) throw const FormatException('数据包过大');
    }

    // 校验 meta
    final metaFile = archive.find(metaFileName);
    if (metaFile == null) {
      throw UnsupportedError('不是有效的数据包（缺少 $metaFileName）');
    }
    final meta = jsonDecode(utf8.decode(metaFile.content));
    if (meta is! Map || meta['type'] != _type) {
      throw UnsupportedError('不是有效的数据包');
    }

    // 校验 formatVersion
    final format = _parseFormat(meta['formatVersion']);
    if (format == null) {
      throw UnsupportedError('不是有效的数据包（缺少合法的 formatVersion）');
    }
    if (format.major > _majorVersion) {
      throw UnsupportedError('数据包格式过新（${format.toVersionString()}），请升级应用后再导入');
    }

    final warning = _warningOf(meta);
    if (warning != null && !await onWarning(warning)) {
      return null;
    }

    // 所有条目先校验，再写入；内存快照用于写入异常回滚。
    final staged = preflight(archive);
    // 原先未开启评论记录时，也将备份中的评论恢复到独立存储，重启后可读取。
    final replyBox =
        GStorage.reply ??
        (staged.containsKey(replyFileName)
            ? await Hive.openBox<Uint8List>('reply')
            : null);
    final boxes = [
      GStorage.setting,
      GStorage.video,
      Accounts.account,
      GStorage.localCache,
      GStorage.historyWord,
      GStorage.userInfo,
      if (replyBox != null) replyBox,
    ];
    final snapshots = [for (final box in boxes) box.toMap()];
    final oldFont = FontUtils.appFont;
    final fontBytes = FontUtils.fontFile.existsSync()
        ? await FontUtils.fontFile.readAsBytes()
        : null;
    final oldBlacklist = Set<int>.from(GlobalData().blackMids);
    final oldRoles = List<Account>.from(Accounts.accountMode);
    final rollback = File('$appSupportDirPath/config-import-recovery.zip');
    final recoveryOut = OutputMemoryStream();
    export(recoveryOut);
    await rollback.writeAsBytes(recoveryOut.getBytes(), flush: true);
    recoveryOut.closeSync();
    try {
      if (staged[settingFileName] case final Map<String, dynamic> settings) {
        await _importSettings(settings);
        await migrateReplyFilterPreferences(GStorage.setting);
        AnonymousAccount().reloadBuvid();
      }
      if (staged[accountFileName] case final Map<String, dynamic> accounts) {
        final parsed = accounts.map(
          (key, value) => MapEntry(key, LoginAccount.fromJson(value)),
        );
        await Accounts.account.clear();
        await Accounts.account.putAll(parsed);
      }
      if (staged[blacklistFileName] case final List<dynamic> list)
        await _importBlacklist(list);
      if (staged[replyFileName] case final List<dynamic> list)
        await _importReply(list, replyBox);
      if (staged[searchFileName] case final List<dynamic> list)
        await _importSearch(list);
      if (staged[fontFileName] case final Uint8List font) {
        final family = GStorage.setting.get(SettingBoxKey.appFont) as String;
        await ui.loadFontFromList(font, fontFamily: family);
        await FontUtils.fontFile.writeAsBytes(font, flush: true);
        FontUtils.appFont = (fontFamily: family, isCustom: true);
      }
      for (final box in boxes) {
        await box.flush();
      }
      await Accounts.refresh(activate: false);
      if (oldRoles[AccountType.main.index] != Accounts.main) {
        await GStorage.userInfo.delete('userInfoCache');
      }
      MineController.anonymity.value = !Accounts.heartbeat.isLogin;
    } catch (error, stack) {
      try {
        for (var i = 0; i < boxes.length; i++) {
          await boxes[i].clear();
          await boxes[i].putAll(snapshots[i]);
          await boxes[i].flush();
        }
        Accounts.accountMode.setAll(0, oldRoles);
        AnonymousAccount().reloadBuvid();
        GlobalData().blackMids
          ..clear()
          ..addAll(oldBlacklist);
        FontUtils.appFont = oldFont;
        if (fontBytes != null) {
          await FontUtils.fontFile.writeAsBytes(fontBytes, flush: true);
          if (oldFont.isCustom)
            await ui.loadFontFromList(
              fontBytes,
              fontFamily: oldFont.fontFamily!,
            );
        } else if (FontUtils.fontFile.existsSync()) {
          await FontUtils.fontFile.delete();
        }
        if (Get.isRegistered<BaseSearchController>()) {
          Get.find<BaseSearchController>().historyList.assignAll(
            List<String>.from(
              GStorage.historyWord.get(_searchCacheKey) ?? const <String>[],
            ),
          );
        }
      } catch (recoveryError) {
        throw StateError('导入失败且恢复未完成，请保留本机恢复文件：$recoveryError');
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      for (final file in archive) {
        file.closeSync();
      }
    }
    if (Get.isRegistered<AccountService>()) {
      final service = Get.find<AccountService>();
      service.face.value = Pref.userInfoCache?.face ?? '';
      service.isLogin.value = Accounts.main.isLogin;
    }
    try {
      await rollback.delete();
    } catch (_) {
      // 数据已导入，恢复副本清理失败不应误报成导入失败。
    }
    return '数据已保存，请重启应用以应用全部设置';
  }

  /// 只解析和验证数据，不修改当前设置或账户。
  static Map<String, dynamic> preflight(Archive archive) {
    final result = <String, dynamic>{};
    var total = 0;
    final names = <String>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      if (!names.add(file.name)) throw const FormatException('数据包含重复文件');
      total += file.size;
      if (total > _maxTotalBytes) throw const FormatException('数据包过大');
      switch (file.name) {
        case settingFileName:
          final data = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(file.content)) as Map,
          );
          if (data['setting'] is! Map || data['video'] is! Map)
            throw const FormatException('设置数据格式不正确');
          result[file.name] = data;
        case accountFileName:
          final data = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(file.content)) as Map,
          );
          final roles = <Object>{};
          for (final entry in data.entries) {
            final account = LoginAccount.fromJson(entry.value);
            if (account.mid.toString() != entry.key)
              throw const FormatException('账户标识不匹配');
            for (final role in account.type) {
              if (!roles.add(role)) throw const FormatException('账户角色重复');
            }
          }
          result[file.name] = data;
        case blacklistFileName:
          final data = jsonDecode(utf8.decode(file.content)) as List;
          Set<int>.from(data);
          result[file.name] = data;
        case replyFileName:
          final data = jsonDecode(utf8.decode(file.content)) as List;
          MyReply.json2ReplyProto(data);
          result[file.name] = data;
        case searchFileName:
          final data = jsonDecode(utf8.decode(file.content)) as List;
          List<String>.from(data);
          result[file.name] = data;
        case fontFileName:
          result[file.name] = Uint8List.fromList(file.content);
      }
    }
    if (result.containsKey(fontFileName)) {
      final settings = result[settingFileName] as Map?;
      final family = (settings?['setting'] as Map?)?[SettingBoxKey.appFont];
      if (family is! String || !family.contains('/'))
        throw const FormatException('数据包缺少字体名');
    }
    return result;
  }

  /// 生成合并警告
  static String? _warningOf(Map meta) {
    final warnings = StringBuffer();

    final format = _parseFormat(meta['formatVersion']);
    if (format != null &&
        format.major == _majorVersion &&
        format.minor > _minorVersion) {
      warnings.writeln('此数据包使用更新的归档格式（${format.toVersionString()}），部分数据可能无法识别');
    }

    final sourceApp = meta['appName'];
    if (sourceApp != Constants.appName) {
      warnings.writeln('此数据包来自「$sourceApp」，与当前应用不同，可能不完全兼容');
    }

    final packageCode = safeToInt(meta['versionCode']);
    if (packageCode != null && packageCode > BuildConfig.versionCode) {
      final versionName = meta['versionName'];
      warnings.writeln(
        '此数据包来自更新版本（v$versionName，构建号 $packageCode），'
        '当前应用较旧（v${BuildConfig.versionName}，构建号 ${BuildConfig.versionCode}），'
        '部分数据可能无法正确还原',
      );
    }
    return warnings.isEmpty ? null : warnings.toString();
  }

  /// 解析 [主, 次] 格式版本
  static VersionCode? _parseFormat(Object? value) {
    if (value is int) {
      return VersionCode(value);
    }
    return null;
  }

  static String _exportAccount() => jsonEncode(Accounts.account.toMap());

  static String _exportBlacklist() => jsonEncode(Pref.blackMids.toList());

  static String? _exportReply() {
    final box = GStorage.reply;
    if (box == null) return null;
    return jsonEncode(
      box.values.map((e) => ReplyInfo.fromBuffer(e).toProto3Json()).toList(),
    );
  }

  static String _exportSearch() {
    final list = GStorage.historyWord.get(_searchCacheKey);
    return jsonEncode(list ?? const <String>[]);
  }

  static String _buildMeta() => jsonEncode({
    'type': _type,
    'formatVersion': const VersionCode.fromMajorMinor(
      _majorVersion,
      _minorVersion,
    ),
    'appName': Constants.appName,
    'versionCode': BuildConfig.versionCode,
    'versionName': BuildConfig.versionName,
    'commitHash': BuildConfig.commitHash,
    'buildTime': BuildConfig.buildTime,
    'platform': DeviceUtils.platformName,
    'exportTime': DateTime.now().toIso8601String(),
    'files': [
      settingFileName,
      accountFileName,
      blacklistFileName,
      if (GStorage.reply != null) replyFileName,
      searchFileName,
      if (FontUtils.fontFile.existsSync()) fontFileName,
    ],
  });

  static Future<void> _importSettings(Map<String, dynamic> data) async {
    // 先校验结构，避免 clear 后 putAll 失败导致旧设置丢失
    if (data[GStorage.setting.name] is! Map ||
        data[GStorage.video.name] is! Map) {
      throw ArgumentError('设置数据格式不正确');
    }
    await GStorage.importAllJsonSettings(data);
  }

  static Future<void> _importBlacklist(List<dynamic> list) async {
    final validated = Set<int>.from(list);
    // 就地覆盖，保持已有引用
    final set = GlobalData().blackMids
      ..clear()
      ..addAll(validated);
    await GStorage.localCache.put(LocalCacheKey.blackMids, set);
  }

  static Future<void> _importReply(
    List<dynamic> list,
    Box<Uint8List>? box,
  ) async {
    if (box == null) return;
    await box.clear();
    await box.putAll(MyReply.json2ReplyProto(list));
  }

  static Future<void> _importSearch(List<dynamic> list) async {
    final history = List<String>.from(list);
    await GStorage.historyWord.put(_searchCacheKey, history);
    // 同步刷新内存单例，避免被旧列表覆盖
    if (Get.isRegistered<BaseSearchController>()) {
      Get.find<BaseSearchController>().historyList.assignAll(history);
    }
  }
}

extension type VersionCode(int _version) {
  int get major => _version >>> 16;
  int get minor => _version & 0xFFFF;

  const VersionCode.fromMajorMinor(int major, int minor)
    : _version = (major << 16) | minor;

  String toVersionString() => '$major.$minor';
}
