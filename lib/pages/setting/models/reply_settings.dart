import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/models/common/reply/reply_at_match_type.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;

List<SettingsModel> get replySettings => [
  const SwitchModel(
    title: '显示视频评论',
    leading: Icon(MdiIcons.commentTextOutline),
    setKey: SettingBoxKey.showVideoReply,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '显示番剧评论',
    leading: Icon(MdiIcons.commentTextOutline),
    setKey: SettingBoxKey.showBangumiReply,
    defaultVal: true,
  ),
  NormalModel(
    title: '评论折叠行数',
    subtitle: '0行为不折叠',
    leading: const Icon(Icons.compress),
    getTrailing: (theme) => Text(
      '${ReplyItemGrpc.replyLengthLimit}行',
      style: theme.textTheme.titleSmall,
    ),
    onTap: _showReplyLengthDialog,
  ),
  getBanWordModel(
    title: '评论关键词过滤',
    key: SettingBoxKey.banWordForReply,
    onChanged: (value) {
      ReplyGrpc.replyRegExp = value;
      ReplyGrpc.enableFilter = value.pattern.isNotEmpty;
    },
  ),
  const SwitchModel(
    title: '记录评论',
    leading: Icon(Icons.message_outlined),
    setKey: SettingBoxKey.saveReply,
    defaultVal: true,
    needReboot: true,
  ),
  const SwitchModel(
    title: '发评反诈',
    subtitle: '发送评论后检查评论是否可见',
    leading: Icon(CustomIcons.shield_reply),
    setKey: SettingBoxKey.enableCommAntifraud,
    defaultVal: false,
  ),
  if (Platform.isAndroid)
    const SwitchModel(
      title: '使用「哔哩发评反诈」检查评论',
      leading: Icon(
        FontAwesomeIcons.b,
        size: 22,
      ),
      setKey: SettingBoxKey.biliSendCommAntifraud,
      defaultVal: false,
    ),
  SwitchModel(
    title: '屏蔽带货评论',
    leading: const Icon(CustomIcons.shopping_bag_not_interested),
    setKey: SettingBoxKey.antiGoodsReply,
    defaultVal: false,
    onChanged: (value) => ReplyGrpc.antiGoodsReply = value,
  ),
  NormalModel(
    title: '屏蔽@评论',
    getSubtitle: () {
      final replyAtBlockType = Pref.replyAtBlockType;
      switch (replyAtBlockType.$2) {
        case .disable:
          return '禁用';
        case .count:
          return '屏蔽${replyAtBlockType.$1}个@及以上的评论';
        case .atOnly:
          return '屏蔽只包含@评论';
      }
    },
    leading: const Icon(Icons.alternate_email),
    onTap: _showReplyAtBlockDialog,
  ),
  SwitchModel(
    title: '评论区搜索关键词',
    subtitle: '展示评论区搜索关键词',
    leading: const Icon(Icons.search_outlined),
    setKey: SettingBoxKey.enableWordRe,
    defaultVal: false,
    onChanged: (value) => ReplyItemGrpc.enableWordRe = value,
  ),
  const SwitchModel(
    title: '默认展示评论区',
    subtitle: '在视频详情页默认切换至评论区页（仅Tab型布局）',
    leading: Icon(Icons.mode_comment_outlined),
    setKey: SettingBoxKey.defaultShowComment,
    defaultVal: false,
  ),
  PopupModel(
    title: '评论展示',
    leading: const Icon(Icons.whatshot_outlined),
    value: () => Pref.replySortType,
    items: ReplySortType.values.take(2),
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.replySortType, value.index)
        .whenComplete(setState),
  ),
  PopupModel(
    title: '楼中楼评论展示',
    leading: const Icon(Icons.subdirectory_arrow_right_outlined),
    value: () => Pref.reply2SortType,
    items: ReplySortType.values.take(2),
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.reply2SortType, value.index)
        .whenComplete(setState),
  ),
];

void _showReplyLengthDialog(BuildContext context, VoidCallback setState) {
  String replyLengthLimit = ReplyItemGrpc.replyLengthLimit.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('评论折叠行数'),
      content: TextFormField(
        autofocus: true,
        initialValue: replyLengthLimit,
        keyboardType: TextInputType.number,
        onChanged: (value) => replyLengthLimit = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: '行'),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final val = int.parse(replyLengthLimit);
              Get.back();
              ReplyItemGrpc.replyLengthLimit = val == 0 ? null : val;
              await GStorage.setting.put(SettingBoxKey.replyLengthLimit, val);
              setState();
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<void> _showReplyAtBlockDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final replyAtBlockType = Pref.replyAtBlockType;
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '屏蔽@评论',
      value: replyAtBlockType.$1 ?? replyAtBlockType.$2.value,
      values: [
        ...ReplyAtBlockType.values.map((e) => (e.value, e.label)),
        if (replyAtBlockType.$1 case final count? when count > 0)
          (count, '屏蔽$count个及以上'),
      ],
    ),
  );
  if (res == null) return;
  if (res == ReplyAtBlockType.disable.value) {
    await Pref.updateReplyAtBlockType(res, .disable);
    setState();
  } else if (res == ReplyAtBlockType.atOnly.value) {
    await Pref.updateReplyAtBlockType(res, .atOnly);
    setState();
  } else {
    if (!context.mounted) return;
    String? countStr;
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('屏蔽@的数量'),
        content: TextFormField(
          autofocus: true,
          keyboardType: .number,
          initialValue: countStr,
          onChanged: (value) => countStr = value,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: Get.back,
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (countStr != null) {
      try {
        final count = int.parse(countStr!);
        if (count > 0) {
          await Pref.updateReplyAtBlockType(count, .count);
          setState();
        }
      } catch (e) {
        SmartDialog.showToast(e.toString());
      }
    }
  }
}
