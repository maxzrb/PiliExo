import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/common_btn.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class TranslationSubtitleButton extends StatelessWidget {
  const TranslationSubtitleButton({
    super.key,
    required this.controller,
    required this.width,
    this.includeDubbing = true,
  });

  final VideoDetailController controller;
  final double width;
  final bool includeDubbing;

  @override
  Widget build(BuildContext context) => Obx(() {
    if (includeDubbing
        ? controller.audioLanguageOptions.isEmpty
        : controller.subtitles.isEmpty) {
      return const SizedBox.shrink();
    }
    return ComBtn(
      width: width,
      height: 30,
      tooltip: '翻译与字幕',
      onTap: () => TranslationSubtitlePanel.show(
        context,
        controller,
        includeDubbing: includeDubbing,
      ),
      icon: const Icon(
        Icons.closed_caption_outlined,
        size: 21,
        color: Colors.white,
      ),
    );
  });
}

class TranslationSubtitlePanel extends StatelessWidget {
  const TranslationSubtitlePanel({
    super.key,
    required this.controller,
    this.includeDubbing = true,
  });

  final VideoDetailController controller;
  final bool includeDubbing;

  static Future<void>? show(
    BuildContext context,
    VideoDetailController controller, {
    bool includeDubbing = true,
  }) => PageUtils.showVideoBottomSheet(
    context,
    maxWidth: 512,
    child: TranslationSubtitlePanel(
      controller: controller,
      includeDubbing: includeDubbing,
    ),
  );

  Widget _choice(String title, bool selected, VoidCallback? onTap) => ListTile(
    dense: true,
    selected: selected,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: selected ? const Icon(Icons.check, size: 16) : null,
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '翻译与字幕',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(child: Obx(_buildTracks)),
          ],
        ),
      ),
    );
  }

  Widget _buildTracks() {
    final dubbing = includeDubbing
        ? controller.audioLanguageOptions
        : const <({String code, String title})>[];
    final subtitles = controller.subtitles;
    final hasDubbing = dubbing.isNotEmpty;
    final hasSubtitles = subtitles.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasDubbing)
          Expanded(
            key: const ValueKey('dubbing'),
            child: _TrackColumn(
              title: '配音语言',
              choices: [
                for (final item in dubbing)
                  _choice(
                    item.title,
                    item.code == (controller.currLang.value ?? ''),
                    controller.switchingAudioLanguage.value
                        ? null
                        : () => controller.setLanguage(item.code),
                  ),
              ],
            ),
          ),
        if (hasDubbing && hasSubtitles) const VerticalDivider(width: 1),
        if (hasSubtitles)
          Expanded(
            key: const ValueKey('subtitles'),
            child: _TrackColumn(
              title: '字幕',
              choices: [
                _choice(
                  '关闭字幕',
                  controller.vttSubtitlesIndex.value <= 0,
                  () => controller.setSubtitle(0),
                ),
                for (var i = 0; i < subtitles.length; i++)
                  _choice(
                    subtitles[i].lanDoc ?? subtitles[i].lan,
                    controller.vttSubtitlesIndex.value == i + 1,
                    () => controller.setSubtitle(i + 1),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrackColumn extends StatelessWidget {
  const _TrackColumn({required this.title, required this.choices});

  final String title;
  final List<Widget> choices;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge),
      ),
      Expanded(
        child: ListView(
          primary: false,
          padding: const EdgeInsets.only(bottom: 12),
          children: choices,
        ),
      ),
    ],
  );
}
