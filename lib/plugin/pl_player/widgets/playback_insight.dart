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
/// 显示模式参考 BiliPai：显示模式常驻，智能模式由控制条和播放事件分别触发。
/// 控制条可覆盖并关闭当前事件窗口；未发生控制条交互时，起播和掉帧摘要各自显示 5 秒后渐隐。
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
  StreamSubscription? _controlsListener;
  // 智能模式的控制条触发和起播/掉帧事件触发必须相互独立。
  var _smartControlVisible = false;
  var _smartAlertVisible = false;
  var _lastDroppedFrames = -1;
  var _detailsExpanded = false;
  var _initialWindowShown = false;

  bool get _smartVisible {
    // 控制条是优先来源；没有控制条时才显示起播/掉帧事件窗口。
    if (_smartControlVisible) return true;
    return _smartAlertVisible;
  }

  @override
  void initState() {
    super.initState();
    _smartControlVisible = widget.controller.showControls.value;
    _lastDroppedFrames = widget.controller.playbackInsight.value.droppedFrames;
    widget.controller.playbackInsight.addListener(_onSnapshotChanged);
    playbackInsightModeNotifier.addListener(_onModeChanged);
    _controlsListener = widget.controller.showControls.listen(
      _onControlsChanged,
    );

    final snapshot = widget.controller.playbackInsight.value;
    if (snapshot.hasMeasuredData &&
        playbackInsightModeNotifier.value == PlaybackInsightMode.smart) {
      _initialWindowShown = true;
      _showSmartWindow();
    }
  }

  void _onSnapshotChanged() {
    final snapshot = widget.controller.playbackInsight.value;
    if (!snapshot.hasMeasuredData) {
      _initialWindowShown = false;
      _detailsExpanded = false;
      _clearSmartAlertWindow();
    }
    final isInitialMeasurement =
        snapshot.hasMeasuredData && !_initialWindowShown;
    if (isInitialMeasurement) {
      _initialWindowShown = true;
    }
    final hasNewDroppedFrames = snapshot.droppedFrames > _lastDroppedFrames;
    _lastDroppedFrames = snapshot.droppedFrames;
    if ((hasNewDroppedFrames || isInitialMeasurement) &&
        playbackInsightModeNotifier.value == PlaybackInsightMode.smart) {
      _showSmartWindow();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _showSmartWindow() {
    // 这里只重置起播/掉帧事件窗口，不能影响控制条触发的显示状态。
    _smartHideTimer?.cancel();
    _smartHideTimer = null;
    if (_smartControlVisible) {
      // 控制条打开时由控制条接管显示，自动事件不应继续覆盖视频内容。
      _smartAlertVisible = false;
      if (mounted) setState(() {});
      return;
    }
    if (mounted) {
      setState(() => _smartAlertVisible = true);
    } else {
      _smartAlertVisible = true;
    }
    _smartHideTimer = Timer(const Duration(seconds: 5), () {
      _smartHideTimer = null;
      if (mounted) {
        setState(() => _smartAlertVisible = false);
      }
    });
  }

  void _clearSmartAlertWindow() {
    _smartHideTimer?.cancel();
    _smartHideTimer = null;
    _smartAlertVisible = false;
  }

  void _onControlsChanged(bool visible) {
    final wasVisible = _smartControlVisible;
    _smartControlVisible = visible;
    if (playbackInsightModeNotifier.value == PlaybackInsightMode.smart &&
        visible != wasVisible) {
      // 控制条打开或关闭都结束自动摘要窗口；查看详情时不能因此收起详情。
      _clearSmartAlertWindow();
    }
    if (mounted) setState(() {});
  }

  void _onModeChanged() {
    if (playbackInsightModeNotifier.value != PlaybackInsightMode.smart) {
      _clearSmartAlertWindow();
    }
    final snapshot = widget.controller.playbackInsight.value;
    if (playbackInsightModeNotifier.value == PlaybackInsightMode.smart) {
      if (snapshot.hasMeasuredData && !_initialWindowShown) {
        _initialWindowShown = true;
        _showSmartWindow();
      }
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
    _controlsListener?.cancel();
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
    final hasHudData =
        snapshot.hasMeasuredData && mode != PlaybackInsightMode.off;

    return LayoutBuilder(
      builder: (context, constraints) {
        final topPadding = widget.isFullScreen ? 80.0 : 44.0;
        final endPadding = widget.isFullScreen ? 36.0 : 14.0;
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - endPadding,
        );
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - topPadding - 12,
        );
        // 全屏详情沿用摘要的实际宽度，只向下扩展纵向空间。
        final fullScreenDetailWidth = math.min(
          availableWidth,
          _playbackInsightSummaryWidth(context, snapshot),
        );
        final fullScreenDetailHeight = math.min(360.0, availableHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_detailsExpanded)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeDetails,
                  child: const ColoredBox(color: Color(0x1F000000)),
                ),
              ),
            if (hasHudData || _detailsExpanded)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                top: _detailsExpanded && !widget.isFullScreen ? 12 : topPadding,
                right: endPadding,
                bottom: _detailsExpanded && !widget.isFullScreen ? 12 : null,
                left: _detailsExpanded && !widget.isFullScreen ? 12 : null,
                width: _detailsExpanded && widget.isFullScreen
                    ? fullScreenDetailWidth
                    : null,
                height: _detailsExpanded && widget.isFullScreen
                    ? fullScreenDetailHeight
                    : null,
                child: IgnorePointer(
                  ignoring: !_detailsExpanded && !insightVisible,
                  child: AnimatedOpacity(
                    opacity: _detailsExpanded || insightVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: Material(
                      color: _detailsExpanded
                          ? const Color(0xD9000000)
                          : const Color(0xAD000000),
                      elevation: _detailsExpanded ? 8 : 0,
                      borderRadius: BorderRadius.circular(
                        _detailsExpanded ? 14 : 10,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _detailsExpanded
                            ? _PlaybackInsightExpandedContent(
                                key: const ValueKey('expanded'),
                                snapshot: snapshot,
                                onDismiss: _closeDetails,
                              )
                            : IgnorePointer(
                                key: const ValueKey('summary'),
                                ignoring: !insightVisible,
                                child: GestureDetector(
                                  onTap: _toggleDetails,
                                  child: _PlaybackInsightSummary(
                                    snapshot: snapshot,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlaybackInsightSummary extends StatelessWidget {
  const _PlaybackInsightSummary({required this.snapshot});

  final PlaybackInsightSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
    );
  }
}

double _playbackInsightSummaryWidth(
  BuildContext context,
  PlaybackInsightSnapshot snapshot,
) {
  final textScaler = MediaQuery.textScalerOf(context);
  final textDirection = Directionality.of(context);
  final defaultStyle = DefaultTextStyle.of(context).style;

  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: defaultStyle.merge(style),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  final textWidth = math.max(
    measure(
      snapshot.summary,
      const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    measure(
      snapshot.statusText,
      const TextStyle(
        color: Color(0xBFFFFFFF),
        fontSize: 10,
      ),
    ),
  );
  // 摘要的水平内边距、状态圆点和两者之间的间距。
  return textWidth + 10 * 2 + 9 + 7;
}

/// 洞察摘要所在的黑色 surface 点击后直接扩展为详情层。
class _PlaybackInsightExpandedContent extends StatelessWidget {
  const _PlaybackInsightExpandedContent({
    super.key,
    required this.snapshot,
    required this.onDismiss,
  });

  final PlaybackInsightSnapshot snapshot;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '播放器洞察',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      snapshot.statusText,
                      style: const TextStyle(
                        color: Color(0xBFFFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusDot(snapshot: snapshot),
              TextButton(
                onPressed: () =>
                    Utils.copyText(_buildPlaybackInsightReport(snapshot)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('复制'),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0x44FFFFFF)),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InsightOverlaySection(
                    title: '概览',
                    rows: snapshot.overviewRows,
                  ),
                  _InsightOverlaySection(
                    title: '视频',
                    rows: snapshot.videoRows,
                  ),
                  _InsightOverlaySection(
                    title: '音频',
                    rows: snapshot.audioRows,
                  ),
                  _InsightOverlaySection(
                    title: '播放',
                    rows: snapshot.runtimeRows,
                  ),
                  _InsightOverlaySection(
                    title: '事件',
                    rows: snapshot.eventRows,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightOverlaySection extends StatelessWidget {
  const _InsightOverlaySection({required this.title, required this.rows});

  final String title;
  final List<PlaybackInsightRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        color: Color(0xBFFFFFFF),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Text(
                      row.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
