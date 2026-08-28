import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:material_ui/material_ui.dart';

/// 打开播放器洞察面板。
///
/// 面板只展示播放器已经报告的实时数据；它不会改变播放后端、解码器或画面输出。
void showPlaybackInsight(
  BuildContext context,
  PlPlayerController controller,
) {
  showDialog<void>(
    context: context,
    builder: (_) => _PlaybackInsightDialog(controller: controller),
  );
}

class _PlaybackInsightDialog extends StatelessWidget {
  const _PlaybackInsightDialog({required this.controller});

  final PlPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackInsightSnapshot>(
      valueListenable: controller.playbackInsight,
      builder: (context, snapshot, child) {
        final colorScheme = ColorScheme.of(context);
        final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('播放器洞察')),
              _StatusDot(snapshot: snapshot),
            ],
          ),
          contentPadding: const EdgeInsets.only(top: 4),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SelectionArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                        child: Text(
                          '${snapshot.summary}\n${snapshot.statusText}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                      _InsightSection(
                        title: '概览',
                        rows: snapshot.overviewRows,
                        initiallyExpanded: true,
                      ),
                      _InsightSection(
                        title: '视频',
                        rows: snapshot.videoRows,
                        initiallyExpanded: true,
                      ),
                      _InsightSection(
                        title: '音频',
                        rows: snapshot.audioRows,
                      ),
                      _InsightSection(
                        title: '播放',
                        rows: snapshot.runtimeRows,
                      ),
                      _InsightSection(
                        title: '事件',
                        rows: snapshot.eventRows,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Utils.copyText(_buildReport(snapshot)),
              child: const Text('复制'),
            ),
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: Text(
                '关闭',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _buildReport(PlaybackInsightSnapshot snapshot) {
    final sections = <List<PlaybackInsightRow>>[
      snapshot.overviewRows,
      snapshot.videoRows,
      snapshot.audioRows,
      snapshot.runtimeRows,
      snapshot.eventRows,
    ];
    return [
      'PiliExo 播放器洞察',
      for (final rows in sections)
        for (final row in rows) '${row.label}: ${row.value}',
    ].join('\n');
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.snapshot});

  final PlaybackInsightSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = snapshot.lastError.isNotEmpty
        ? const Color(0xFFE57373)
        : snapshot.droppedFrames > 0 ||
              (snapshot.isBuffering && snapshot.playWhenReady)
        ? const Color(0xFFFFB74D)
        : const Color(0xFF66E28A);
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({
    required this.title,
    required this.rows,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<PlaybackInsightRow> rows;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: initiallyExpanded,
      dense: true,
      children: [
        for (final row in rows)
          ListTile(
            dense: true,
            title: Text(row.label),
            subtitle: Text(row.value),
          ),
      ],
    );
  }
}
