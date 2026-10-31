import 'package:hive_ce/hive.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// 新键存在时尊重用户选择，否则将旧互斥设置迁移为两个独立选项。
Future<void> migrateReplyFilterPreferences(Box box) async {
  final old = box.get('replyAtBlockType');
  if (!box.containsKey(SettingBoxKey.blockAtOnlyReply)) {
    await box.put(SettingBoxKey.blockAtOnlyReply, old == -1);
  }
  if (!box.containsKey(SettingBoxKey.blockReplyAtCount)) {
    await box.put(
      SettingBoxKey.blockReplyAtCount,
      old is int && old > 0 ? old : null,
    );
  }
}
