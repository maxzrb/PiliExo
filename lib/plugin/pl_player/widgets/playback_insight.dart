import 'dart:async';
import 'dart:math' as math;

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
  var _detailsExpanded = false;

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
    if (playbackInsightModeNotifier.value == PlaybackInsightMode.off) {
      _detailsExpanded = false;
    }
    if (mounted) setState(() {});
  }

  void _toggleDetails() {
    if (!mounted) return;
    setState(() => _detailsExpanded = !_detailsExpanded);
  }

  void _closeDetails() {
    if (!mounted) return;
    setState(() => _detailsExpanded = false);
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
    final insightVisible =
        snapshot.hasMeasuredData &&
        switch (mode) {
          PlaybackInsightMode.always => true,
          PlaybackInsightMode.smart => _smartVisible,
          PlaybackInsightMode.off => false,
        };
    final showHud = _detailsExpanded || insightVisible;

    return LayoutBuilder(
      builder: (context, constraints) {
        final topPadding = widget.isFullScreen ? 80.0 : 44.0;
        final endPadding = widget.isFullScreen ? 24.0 : 14.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showHud)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: topPadding,
                    right: endPadding,
                  ),
                  child: AnimatedOpacity(
                    opacity: insightVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: IgnorePointer(
                      ignoring: !insightVisible,
                      child: GestureDetector(
                        onTap: _toggleDetails,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xAD000000),
                            borderRadius: BorderRadius.all(
                              Radius.circular(10),
                            ),
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
              ),
            if (_detailsExpanded) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeDetails,
                  child: const ColoredBox(color: Color(0x1F000000)),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _PlaybackInsightPanel(
                    controller: widget.controller,
                    onDismiss: _closeDetails,
                    availableWidth: constraints.maxWidth - 16,
                    availableHeight: constraints.maxHeight - 16,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 洞察摘要点击后在播放器同一层展开，避免再弹出一个二级对话框。
class _PlaybackInsightPanel extends StatelessWidget {
  const _PlaybackInsightPanel({
    required this.controller,
    required this.onDismiss,
    required this.availableWidth,
    required this.availableHeight,
  });

  final PlPlayerController controller;
  final VoidCallback onDismiss;
  final double availableWidth;
  final double availableHeight;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackInsightSnapshot>(
      valueListenable: controller.playbackInsight,
      builder: (context, snapshot, child) {
        final colorScheme = ColorScheme.of(context);
        final isLandscape = availableWidth > availableHeight;
        final preferredWidth = isLandscape
            ? math.max(260.0, availableWidth * 0.42)
            : math.min(440.0, availableWidth - 24);
        final panelWidth = math.max(
          0.0,
          math.min(availableWidth, preferredWidth),
        );
        final preferredHeight = isLandscape
            ? math.min(360.0, availableHeight)
            : math.min(520.0, availableHeight * 0.84);
        final panelHeight = math.max(
          0.0,
          math.min(availableHeight, preferredHeight),
        );
        return Material(
          color: colorScheme.surface.withValues(alpha: 0.96),
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: panelWidth,
            height: panelHeight,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '播放器洞察',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _StatusDot(snapshot: snapshot),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: onDismiss,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _PlaybackInsightBody(snapshot: snapshot),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Utils.copyText(
                          _buildPlaybackInsightReport(snapshot),
                        ),
                        child: const Text('复制'),
                      ),
                      TextButton(
                        onPressed: onDismiss,
                        child: Text(
                          '关闭',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              child: _PlaybackInsightBody(
                snapshot: snapshot,
                colorScheme: colorScheme,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Utils.copyText(_buildPlaybackInsightReport(snapshot)),
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
}

class _PlaybackInsightBody extends StatelessWidget {
  const _PlaybackInsightBody({
    required this.snapshot,
    this.colorScheme,
  });

  final PlaybackInsightSnapshot snapshot;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final resolvedColorScheme = colorScheme ?? ColorScheme.of(context);
    return SelectionArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '${snapshot.summary}\n${snapshot.statusText}',
                style: TextStyle(
                  color: resolvedColorScheme.onSurfaceVariant,
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
            _InsightSection(title: '音频', rows: snapshot.audioRows),
            _InsightSection(title: '播放', rows: snapshot.runtimeRows),
            _InsightSection(title: '事件', rows: snapshot.eventRows),
          ],
        ),
      ),
    );
  }
}

String _buildPlaybackInsightReport(PlaybackInsightSnapshot snapshot) {
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
