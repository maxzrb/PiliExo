import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight_mode.dart';
import 'package:PiliPlus/plugin/pl_player/utils/playback_insight_settings.dart';
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

/// 在播放器右上角显示洞察摘要。
///
/// 显示模式参考 BiliPai：显示模式常驻，智能模式只在检测到新掉帧时出现。
/// 智能模式的掉帧摘要显示 5 秒后开始渐隐，避免遮挡视频内容。
class PlaybackInsightHud extends StatefulWidget {
  const PlaybackInsightHud({
    super.key,
    required this.controller,
    required this.isFullScreen,
  });

  final PlPlayerController controller;
  final bool isFullScreen;

  @override
  State<PlaybackInsightHud> createState() => _PlaybackInsightHudState();
}

class _PlaybackInsightHudState extends State<PlaybackInsightHud> {
  Timer? _smartHideTimer;
  var _smartVisible = false;
  var _lastDroppedFrames = -1;

  @override
  void initState() {
    super.initState();
    _lastDroppedFrames = widget.controller.playbackInsight.value.droppedFrames;
    widget.controller.playbackInsight.addListener(_onSnapshotChanged);
    playbackInsightModeNotifier.addListener(_onModeChanged);
  }

  void _onSnapshotChanged() {
    final snapshot = widget.controller.playbackInsight.value;
    final hasNewDroppedFrames = snapshot.droppedFrames > _lastDroppedFrames;
    _lastDroppedFrames = snapshot.droppedFrames;
    if (hasNewDroppedFrames &&
        playbackInsightModeNotifier.value == PlaybackInsightMode.smart) {
      _smartHideTimer?.cancel();
      if (mounted) {
        setState(() => _smartVisible = true);
      } else {
        _smartVisible = true;
      }
      _smartHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _smartVisible = false);
        }
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  void _onModeChanged() {
    if (playbackInsightModeNotifier.value != PlaybackInsightMode.smart) {
      _smartHideTimer?.cancel();
      _smartVisible = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _smartHideTimer?.cancel();
    widget.controller.playbackInsight.removeListener(_onSnapshotChanged);
    playbackInsightModeNotifier.removeListener(_onModeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.playbackInsight.value;
    final mode = playbackInsightModeNotifier.value;
    final visible =
        snapshot.hasMeasuredData &&
        switch (mode) {
          PlaybackInsightMode.always => true,
          PlaybackInsightMode.smart => _smartVisible,
          PlaybackInsightMode.off => false,
        };
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.isFullScreen ? 14 : 8,
          right: 10,
        ),
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          child: IgnorePointer(
            ignoring: !visible,
            child: GestureDetector(
              onTap: () => showPlaybackInsight(context, widget.controller),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xAD000000),
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusDot(snapshot: snapshot),
                      const SizedBox(width: 7),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            snapshot.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            snapshot.statusText,
                            style: const TextStyle(
                              color: Color(0xBFFFFFFF),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
