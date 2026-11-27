import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/recommend_mix.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get recommendSettings {
  var appRatio = Pref.appRcmdRatio;
  var pendingRefresh = Pref.appRcmdRatioPending;
  return [
    NormalModel(
      title: '首页推荐来源',
      leading: const Icon(Icons.model_training_outlined),
      getSubtitle: () => RecommendMix.describeRatio(
        appRatio,
        pending: pendingRefresh,
      ),
      onTap: (context, setState) async {
        final value = await showDialog<double>(
          context: context,
          builder: (context) => SliderDialog(
            title: const Text('首页推荐来源'),
            value: appRatio.toDouble(),
            min: RecommendMix.minAppRatio.toDouble(),
            max: RecommendMix.maxAppRatio.toDouble(),
            divisions: RecommendMix.maxAppRatio ~/ RecommendMix.ratioStep,
            precise: 0,
            suffix: '%',
            minLabel: 'Web 推荐',
            maxLabel: 'App 推荐',
          ),
        );
        if (value == null || !context.mounted) return;
        final nextRatio = RecommendMix.normalizeRatio(value);
        final changed = nextRatio != appRatio;
        appRatio = nextRatio;
        if (changed) {
          pendingRefresh = true;
        }
        await GStorage.setting.put(SettingBoxKey.appRcmdRatio, appRatio);
        if (changed) {
          await GStorage.setting.put(
            SettingBoxKey.appRcmdRatioPending,
            true,
          );
        }
        if (!context.mounted) return;
        setState();
        SmartDialog.showToast(changed ? '已保存，下次刷新生效' : '设置未改变');
      },
    ),
    SwitchModel(
      title: '保留首页推荐刷新',
      subtitle: '下拉刷新时保留上次内容',
      leading: const Icon(Icons.refresh),
      setKey: SettingBoxKey.enableSaveLastData,
      defaultVal: true,
      onChanged: (value) {
        try {
          Get.find<RcmdController>()
            ..enableSaveLastData = value
            ..lastRefreshAt = null;
        } catch (e) {
          if (kDebugMode) debugPrint('$e');
        }
      },
    ),
    SwitchModel(
      title: '显示上次看到位置提示',
      subtitle: '保留上次推荐时，在上次刷新位置显示提示',
      leading: const Icon(Icons.tips_and_updates_outlined),
      setKey: SettingBoxKey.savedRcmdTip,
      defaultVal: true,
      onChanged: (value) {
        try {
          Get.find<RcmdController>()
            ..savedRcmdTip = value
            ..lastRefreshAt = null;
        } catch (e) {
          if (kDebugMode) debugPrint('$e');
        }
      },
    ),
    getVideoFilterSelectModel(
      title: '点赞率',
      suffix: '%',
      key: SettingBoxKey.minLikeRatioForRecommend,
      filterScope: 'Web推荐、热门、分区',
      values: [0, 1, 2, 3, 4],
      onChanged: (value) => RecommendFilter.minLikeRatioForRecommend = value,
    ),
    getBanWordModel(
      title: '标题关键词过滤',
      key: SettingBoxKey.banWordForRecommend,
      banScope: '推荐、热门、分区、相关视频',
      onChanged: (value) {
        RecommendFilter.rcmdRegExp = value;
        RecommendFilter.enableFilter = value.pattern.isNotEmpty;
      },
    ),
    getBanWordModel(
      title: '分区关键词过滤',
      key: SettingBoxKey.banWordForZone,
      banScope: 'App推荐、热门、分区',
      onChanged: (value) {
        VideoHttp.zoneRegExp = value;
        VideoHttp.enableFilter = value.pattern.isNotEmpty;
      },
    ),
    getBanWordModel(
      title: 'UP 主昵称关键词过滤',
      key: SettingBoxKey.banWordForRecommendUpName,
      banScope: '推荐及启用完整过滤的列表',
      onChanged: (value) => RecommendFilter.upNameRegExp = value,
    ),
    _recommendAuthorList(
      title: '推荐屏蔽 UP 主',
      key: SettingBoxKey.recommendBlockedMids,
      values: () => Pref.recommendBlockedMids,
      onChanged: (ids) => RecommendFilter.blockedMids = ids,
    ),
    _recommendAuthorList(
      title: '推荐白名单',
      key: SettingBoxKey.recommendAllowedMids,
      values: () => Pref.recommendAllowedMids,
      onChanged: (ids) => RecommendFilter.allowedMids = ids,
    ),
    const SwitchModel(
      title: '隐藏无权播放的视频',
      subtitle: '适用于 App 推荐中的视频',
      leading: Icon(Icons.block_outlined),
      setKey: SettingBoxKey.filterUnplayableAppRecommend,
      defaultVal: true,
    ),
    getVideoFilterSelectModel(
      title: '视频时长',
      suffix: 's',
      key: SettingBoxKey.minDurationForRcmd,
      filterScope: '推荐、相关视频',
      values: [0, 30, 60, 90, 120],
      onChanged: (value) => RecommendFilter.minDurationForRcmd = value,
    ),
    getVideoFilterSelectModel(
      title: '播放量',
      key: SettingBoxKey.minPlayForRcmd,
      filterScope: '推荐、热门、分区、相关视频',
      values: [0, 50, 100, 500, 1000],
      onChanged: (value) => RecommendFilter.minPlayForRcmd = value,
    ),
    SwitchModel(
      title: '已关注UP豁免推荐过滤',
      subtitle: '已关注 UP 主可跳过常规条件，屏蔽名单优先生效',
      leading: const Icon(Icons.favorite_border_outlined),
      setKey: SettingBoxKey.exemptFilterForFollowed,
      defaultVal: true,
      onChanged: (value) => RecommendFilter.exemptFilterForFollowed = value,
    ),
    SwitchModel(
      title: '过滤器也应用于详情页相关视频',
      subtitle: '支持标题、昵称、时长、播放量和用户名单过滤',
      leading: const Icon(Icons.explore_outlined),
      setKey: SettingBoxKey.applyFilterToRelatedVideos,
      defaultVal: true,
      onChanged: (value) => RecommendFilter.applyFilterToRelatedVideos = value,
    ),
    const SwitchModel(
      title: '完整过滤也应用于热门视频',
      leading: Icon(Icons.local_fire_department_outlined),
      setKey: SettingBoxKey.applyFilterToHotVideos,
      defaultVal: false,
    ),
    const SwitchModel(
      title: '完整过滤也应用于视频排行',
      leading: Icon(Icons.leaderboard_outlined),
      setKey: SettingBoxKey.applyFilterToRankVideos,
      defaultVal: false,
    ),
  ];
}

SettingsModel _recommendAuthorList({
  required String title,
  required String key,
  required List<int> Function() values,
  required void Function(Set<int>) onChanged,
}) => NormalModel(
  title: title,
  leading: const Icon(Icons.person_outline),
  getSubtitle: () => '已添加 ${values().length} 位 UP 主',
  onTap: (context, refresh) async {
    var input = values().join('\n');
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          initialValue: input,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: '输入 UID，用空格、逗号或换行分隔'),
          onChanged: (value) => input = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final ids = <int>{};
              for (final value in input.split(RegExp(r'[\s,，]+'))) {
                if (value.isEmpty) continue;
                final id = int.tryParse(value);
                if (id == null || id <= 0) {
                  SmartDialog.showToast('UID 应为正整数');
                  return;
                }
                ids.add(id);
              }
              Navigator.pop(context, ids);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      await GStorage.setting.put(key, result.toList());
      onChanged(result);
      refresh();
    }
  },
);
