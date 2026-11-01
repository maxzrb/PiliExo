import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/reply_filter_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:fixnum/fixnum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-upstream-');
    appSupportDirPath = directory.path;
    Hive.init(directory.path);
    GStorage.regAdapter();
    box = await Hive.openBox('setting');
    GStorage.setting = box;
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.historyWord = await Hive.openBox('historyWord');
    GStorage.userInfo = await Hive.openBox<UserInfoData>('userInfo');
    Accounts.account = await Hive.openBox<LoginAccount>('account');
    GStorage.reply = null;
  });
  setUp(() => box.clear());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('旧纯@设置迁移且再次迁移尊重新设置', () async {
    await box.put('replyAtBlockType', -1);
    await migrateReplyFilterPreferences(box);
    expect(box.get(SettingBoxKey.blockAtOnlyReply), isTrue);
    await box.put(SettingBoxKey.blockAtOnlyReply, false);
    await migrateReplyFilterPreferences(box);
    expect(box.get(SettingBoxKey.blockAtOnlyReply), isFalse);
  });

  test('旧数量阈值迁移，显式禁用不被旧值恢复', () async {
    await box.put('replyAtBlockType', 3);
    await migrateReplyFilterPreferences(box);
    expect(box.get(SettingBoxKey.blockReplyAtCount), 3);
    await box.put(SettingBoxKey.blockReplyAtCount, null);
    await migrateReplyFilterPreferences(box);
    expect(box.get(SettingBoxKey.blockReplyAtCount), isNull);
  });

  List<VideoItem> videos(List<int> ids) => PlayUrlModel.fromJson({
    'dash': {
      'video': [
        for (final id in ids) {'id': id, 'codecs': 'av01'},
      ],
    },
  }).dash!.video!;

  test('8K排在列表首项时仍精确选择HDR Vivid', () {
    final selected = VideoUtils.findTargetVideo(
      videos([127, 129, 120]),
      129,
      [127, 129, 120],
      null,
      [.AV1],
    );
    expect(selected.$1, 129);
    expect(selected.$4.quality, VideoQuality.hdrVivid);
  });

  test('接口宣称但实际缺失的画质不会产生空轨道访问', () {
    final selected = VideoUtils.findTargetVideo(
      videos([120, 80]),
      116,
      [120, 116, 80],
      [],
      [.AV1],
    );
    expect(selected.$1, 80);
    expect(selected.$4.quality.code, 80);
  });

  test('未知编码和空格式仍保留真实轨道', () {
    final track = videos([120]).single..codecs = 'future-codec';
    final selected = VideoUtils.findTargetVideo(
      [track],
      120,
      null,
      [],
      [VideoDecodeFormatType.HEVC],
    );
    expect(selected.$4, same(track));
    expect(selected.$1, 120);
  });

  test('相同等级的两个杜比音轨仍精确命中用户ID', () {
    final tracks = [
      AudioItem.fromJson({'id': 30250}),
      AudioItem.fromJson({'id': 30255}),
    ];
    expect(VideoUtils.findTargetAudio(tracks, 30255).id, 30255);
  });

  test('备份预检拒绝重复条目', () {
    final archive = Archive()
      ..add(ArchiveFile.string('setting.json', '{"setting":{},"video":{}}'))
      ..add(ArchiveFile.string('other.json', '{}'));
    // 构造重复名称，验证预检拒绝有歧义的归档条目。
    archive.modifyAtIndex(1, ArchiveFile.string('setting.json', '{}'));
    expect(() => ConfigArchive.preflight(archive), throwsFormatException);
  });

  test('后续黑名单文件损坏时不会提前覆盖设置', () async {
    await box.put('preserved', 'original');
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'meta.json',
          jsonEncode({
            'type': 'data_archive',
            'formatVersion': 65536,
            'appName': Constants.appName,
          }),
        ),
      )
      ..add(
        ArchiveFile.string(
          'setting.json',
          '{"setting":{"preserved":"new"},"video":{}}',
        ),
      )
      ..add(ArchiveFile.string('blacklist.json', '["invalid-id"]'));
    final bytes = ZipEncoder().encode(archive);
    await expectLater(
      ConfigArchive.import(
        Uint8List.fromList(bytes),
        onWarning: (_) async => true,
      ),
      throwsA(anything),
    );
    expect(box.get('preserved'), 'original');
  });
  test('合法备份完成落盘并清理恢复副本，设置及搜索记录同时生效', () async {
    await box.put('preserved', 'original');
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'meta.json',
          jsonEncode({
            'type': 'data_archive',
            'formatVersion': 65536,
            'appName': Constants.appName,
          }),
        ),
      )
      ..add(
        ArchiveFile.string(
          'setting.json',
          '{"setting":{"preserved":"new"},"video":{"speed":1.5}}',
        ),
      )
      ..add(ArchiveFile.string('account.json', '{}'))
      ..add(ArchiveFile.string('blacklist.json', '[123]'))
      ..add(ArchiveFile.string('search.json', '["query"]'));
    final result = await ConfigArchive.import(
      Uint8List.fromList(ZipEncoder().encode(archive)),
      onWarning: (_) async => true,
    );
    expect(result, contains('请重启'));
    expect(box.get('preserved'), 'new');
    expect(GStorage.video.get('speed'), 1.5);
    expect(GStorage.historyWord.get('cacheList'), ['query']);
    expect(GStorage.localCache.get(LocalCacheKey.blackMids), {123});
    expect(
      File('${directory.path}/config-import-recovery.zip').existsSync(),
      isFalse,
    );
  });
  for (final kind in ['crc', 'truncated']) {
    test('损坏ZIP被拒绝且不改写设置：$kind', () async {
      await box.put('preserved', 'original');
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'meta.json',
            jsonEncode({
              'type': 'data_archive',
              'formatVersion': 65536,
              'appName': Constants.appName,
            }),
          ),
        )
        ..add(
          ArchiveFile.string(
            'setting.json',
            '{"setting":{"preserved":"changed"},"video":{}}',
          ),
        );
      var bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      if (kind == 'crc') {
        // 修改首个中央目录CRC，保持JSON内容合法以专门验证ZIP校验。
        var found = false;
        for (var i = 0; i + 46 < bytes.length; i++) {
          if (bytes[i] == 0x50 &&
              bytes[i + 1] == 0x4b &&
              bytes[i + 2] == 0x01 &&
              bytes[i + 3] == 0x02) {
            bytes[i + 16] ^= 0xff;
            found = true;
            break;
          }
        }
        expect(found, isTrue);
      } else {
        bytes = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
      }
      await expectLater(
        ConfigArchive.import(bytes, onWarning: (_) async => true),
        throwsA(anything),
      );
      expect(box.get('preserved'), 'original');
      expect(
        File('${directory.path}/config-import-recovery.zip').existsSync(),
        isFalse,
      );
    });
  }

  test('原先未记录评论时仍恢复备份评论到重启可读的存储', () async {
    final reply = ReplyInfo(id: Int64(123), oid: Int64(456), type: Int64(1));
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'meta.json',
          jsonEncode({
            'type': 'data_archive',
            'formatVersion': 65536,
            'appName': Constants.appName,
          }),
        ),
      )
      ..add(
        ArchiveFile.string('reply.json', jsonEncode([reply.toProto3Json()])),
      );
    expect(GStorage.reply, isNull);
    await ConfigArchive.import(
      Uint8List.fromList(ZipEncoder().encode(archive)),
      onWarning: (_) async => true,
    );
    var restored = await Hive.openBox<Uint8List>('reply');
    await restored.close();
    restored = await Hive.openBox<Uint8List>('reply');
    expect(ReplyInfo.fromBuffer(restored.get('123')!).oid.toInt(), 456);
    await restored.close();
  });
}
