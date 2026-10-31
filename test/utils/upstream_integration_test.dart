import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/reply_filter_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-upstream-');
    Hive.init(directory.path);
    box = await Hive.openBox('setting');
    GStorage.setting = box;
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
}
