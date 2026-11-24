import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/widgets/normal_item.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/router/page_transitions.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

class PredictiveBackSettingPage extends StatefulWidget {
  const PredictiveBackSettingPage({super.key});

  @override
  State<PredictiveBackSettingPage> createState() =>
      _PredictiveBackSettingPageState();
}

class _PredictiveBackSettingPageState extends State<PredictiveBackSettingPage> {
  Future<void> _showStyleDialog(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    final res = await showDialog<PredictiveBackStyle>(
      context: context,
      builder: (context) => SelectDialog<PredictiveBackStyle>(
        title: '效果风格',
        value: PredictiveBackStyle.fromIndex(Pref.predictiveBackStyle),
        values: PredictiveBackStyle.values
            .map((style) => (style, style.label))
            .toList(),
      ),
    );
    if (res == null) return;
    final previous = PredictiveBackStyle.fromIndex(Pref.predictiveBackStyle);
    PageTransitions.selectStyleIndex(res.index);
    if (previous.isSlide != res.isSlide) {
      // 切换分组时按新样式重置渐隐默认值。
      final fade = res.defaultFadePercent;
      PageTransitions.selectMotion(fadePercent: fade);
      await GStorage.setting.put(
        SettingBoxKey.predictiveBackFadePercent,
        fade,
      );
    }
    await GStorage.setting.put(SettingBoxKey.predictiveBackStyle, res.index);
    refresh();
  }

  Future<void> _showSlideDialog(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        value: Pref.predictiveBackSlidePercent.toDouble(),
        title: const Text('滑动位移上限'),
        min: 20,
        max: 100,
        divisions: 16,
        suffix: '%',
        minLabel: '20%',
        maxLabel: '100%',
      ),
    );
    if (res == null) return;
    final percent = res.round();
    PageTransitions.selectMotion(slidePercent: percent);
    await GStorage.setting.put(
      SettingBoxKey.predictiveBackSlidePercent,
      percent,
    );
    refresh();
  }

  Future<void> _showFadeDialog(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        value: Pref.predictiveBackFadePercent.toDouble(),
        title: const Text('渐隐幅度'),
        min: 0,
        max: 100,
        divisions: 20,
        suffix: '%',
        minLabel: '0%',
        maxLabel: '100%',
      ),
    );
    if (res == null) return;
    final percent = res.round();
    PageTransitions.selectMotion(fadePercent: percent);
    await GStorage.setting.put(
      SettingBoxKey.predictiveBackFadePercent,
      percent,
    );
    refresh();
  }

  Future<void> _showScaleDialog(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        value: Pref.predictiveBackScalePercent.toDouble(),
        title: const Text('缩小幅度'),
        min: 0,
        max: 40,
        divisions: 8,
        suffix: '%',
        minLabel: '0%',
        maxLabel: '40%',
      ),
    );
    if (res == null) return;
    final percent = res.round();
    PageTransitions.selectMotion(scalePercent: percent);
    await GStorage.setting.put(
      SettingBoxKey.predictiveBackScalePercent,
      percent,
    );
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('预测性返回')),
      body: ValueListenableBuilder<PredictiveBackStyle>(
        valueListenable: PageTransitions.predictiveBackStyle,
        builder: (context, style, _) {
          final slide = style.isSlide;
          final zoom = style == PredictiveBackStyle.zoomFade;
          return ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  '从屏幕边缘返回时，先预览上一页再松手退出。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              NormalItem(
                title: '效果风格',
                leading: const Icon(Icons.swipe),
                getSubtitle: () => style.label,
                onTap: _showStyleDialog,
              ),
              if (zoom)
                NormalItem(
                  title: '缩小幅度',
                  leading: const Icon(Icons.zoom_out_map),
                  getSubtitle: () =>
                      '返回过程中页面最多缩小 ${Pref.predictiveBackScalePercent}%',
                  getTrailing: (theme) => Text(
                    '${Pref.predictiveBackScalePercent}%',
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: _showScaleDialog,
                ),
              if (slide)
                NormalItem(
                  title: '滑动位移上限',
                  leading: const Icon(Icons.swipe_right_alt),
                  getSubtitle: () =>
                      '页面最多跟手移动屏幕宽度的 ${Pref.predictiveBackSlidePercent}%',
                  getTrailing: (theme) => Text(
                    '${Pref.predictiveBackSlidePercent}%',
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: _showSlideDialog,
                ),
              NormalItem(
                title: '渐隐幅度',
                leading: const Icon(Icons.opacity),
                getSubtitle: () =>
                    '拖动时页面最多淡出 ${Pref.predictiveBackFadePercent}%',
                getTrailing: (theme) => Text(
                  '${Pref.predictiveBackFadePercent}%',
                  style: theme.textTheme.titleSmall,
                ),
                onTap: _showFadeDialog,
              ),
            ],
          );
        },
      ),
    );
  }
}
