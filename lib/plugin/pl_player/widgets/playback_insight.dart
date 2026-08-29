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
  static const _summaryFadeDuration = Duration(milliseconds: 350);

  Timer? _smartHideTimer;
  Timer? _summaryHitTestTimer;
  StreamSubscription? _controlsListener;
  // 智能模式的控制条触发和起播/掉帧事件触发必须相互独立。
  var _smartControlVisible = false;
  var _smartAlertVisible = false;
  var _lastDroppedFrames = -1;
  var _detailsExpanded = false;
  var _initialWindowShown = false;
  var _summaryHitTestEnabled = false;

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
    _summaryHitTestTimer?.cancel();
    _summaryHitTestTimer = null;
    _summaryHitTestEnabled = false;
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
      _keepSummaryHitTestDuringFade();
      if (mounted) {
        setState(() => _smartAlertVisible = false);
      }
    });
  }

  void _keepSummaryHitTestDuringFade() {
    _summaryHitTestTimer?.cancel();
    _summaryHitTestEnabled = true;
    _summaryHitTestTimer = Timer(_summaryFadeDuration, () {
      _summaryHitTestTimer = null;
      if (mounted) {
        setState(() => _summaryHitTestEnabled = false);
      } else {
        _summaryHitTestEnabled = false;
      }
    });
  }

  void _clearSmartAlertWindow() {
    _smartHideTimer?.cancel();
    _smartHideTimer = null;
    _summaryHitTestTimer?.cancel();
    _summaryHitTestTimer = null;
    _summaryHitTestEnabled = false;
    _smartAlertVisible = false;
  }

  void _onControlsChanged(bool visible) {
    final wasVisible = _smartControlVisible;
    final wasInsightVisible = _smartVisible;
    _smartControlVisible = visible;
    if (playbackInsightModeNotifier.value == PlaybackInsightMode.smart &&
        visible != wasVisible) {
      // 控制条打开或关闭都结束自动摘要窗口；查看详情时不能因此收起详情。
      _clearSmartAlertWindow();
      if (!visible && wasInsightVisible) {
        _keepSummaryHitTestDuringFade();
      }
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
    setState(() {
      _detailsExpanded = !_detailsExpanded;
      if (_detailsExpanded) {
        _summaryHitTestTimer?.cancel();
        _summaryHitTestTimer = null;
        _summaryHitTestEnabled = false;
      }
    });
  }

  void _closeDetails() {
    if (!mounted) return;
    setState(() => _detailsExpanded = false);
  }

  @override
  void dispose() {
    _smartHideTimer?.cancel();
    _summaryHitTestTimer?.cancel();
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
    final summaryInteractive = insightVisible || _summaryHitTestEnabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullscreenPolicy = widget.isFullScreen
            ? _resolvePlaybackInsightFullscreenPolicy(constraints.maxWidth)
            : null;
        final topPadding = fullscreenPolicy?.summaryTopPadding ?? 44.0;
        final endPadding = fullscreenPolicy?.summaryEndPadding ?? 14.0;
        final fullScreenDetailWidth = fullscreenPolicy == null
            ? 0.0
            : math.min(
                math.max(
                  0.0,
                  constraints.maxWidth - fullscreenPolicy.detailEdgePadding * 2,
                ),
                math.min(
                  fullscreenPolicy.detailMaxWidth,
                  math.max(
                    fullscreenPolicy.detailMinWidth,
                    constraints.maxWidth * fullscreenPolicy.detailWidthFactor,
                  ),
                ),
              );
        final fullScreenDetailHeight = fullscreenPolicy == null
            ? 0.0
            : math.min(
                fullscreenPolicy.detailMaxHeight,
                math.max(
                  0.0,
                  constraints.maxHeight -
                      fullscreenPolicy.detailEdgePadding * 2,
                ),
              );
        final fullScreenDetailTop = fullscreenPolicy == null
            ? 0.0
            : math.max(
                fullscreenPolicy.detailEdgePadding,
                (constraints.maxHeight - fullScreenDetailHeight) / 2,
              );
        final isFullscreenDetail = _detailsExpanded && widget.isFullScreen;
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
                top: isFullscreenDetail
                    ? fullScreenDetailTop
                    : _detailsExpanded
                    ? 12
                    : topPadding,
                right: isFullscreenDetail
                    ? fullscreenPolicy!.detailEdgePadding
                    : endPadding,
                bottom: _detailsExpanded && !widget.isFullScreen ? 12 : null,
                left: _detailsExpanded && !widget.isFullScreen ? 12 : null,
                width: isFullscreenDetail ? fullScreenDetailWidth : null,
                height: isFullscreenDetail ? fullScreenDetailHeight : null,
                child: IgnorePointer(
                  ignoring: !_detailsExpanded && !summaryInteractive,
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
                            : GestureDetector(
                                key: const ValueKey('summary'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _toggleDetails,
                                child: _PlaybackInsightSummary(
                                  snapshot: snapshot,
                                  fullscreenPolicy: fullscreenPolicy,
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
  const _PlaybackInsightSummary({
    required this.snapshot,
    this.fullscreenPolicy,
  });

  final PlaybackInsightSnapshot snapshot;
  final _PlaybackInsightFullscreenPolicy? fullscreenPolicy;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = fullscreenPolicy?.summaryHorizontalPadding ?? 10;
    final verticalPadding = fullscreenPolicy?.summaryVerticalPadding ?? 7;
    final summaryFontSize = fullscreenPolicy?.summaryFontSize ?? 12;
    final statusFontSize = math.max(9.0, summaryFontSize - 1);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: fullscreenPolicy?.summaryMinHeight ?? 0,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusDot(
              snapshot: snapshot,
              size: fullscreenPolicy?.summaryDotSize ?? 9,
            ),
            SizedBox(
              width: fullscreenPolicy?.summarySpacing ?? 7,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: summaryFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  snapshot.statusText,
                  style: TextStyle(
                    color: const Color(0xBFFFFFFF),
                    fontSize: statusFontSize,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏洞察尺寸策略参考 BiliPai 的播放器覆盖层分档。
class _PlaybackInsightFullscreenPolicy {
  const _PlaybackInsightFullscreenPolicy({
    required this.summaryTopPadding,
    required this.summaryEndPadding,
    required this.summaryHorizontalPadding,
    required this.summaryVerticalPadding,
    required this.summaryMinHeight,
    required this.summaryDotSize,
    required this.summarySpacing,
    required this.summaryFontSize,
    required this.detailEdgePadding,
    required this.detailWidthFactor,
    required this.detailMinWidth,
    required this.detailMaxWidth,
    required this.detailMaxHeight,
  });

  final double summaryTopPadding;
  final double summaryEndPadding;
  final double summaryHorizontalPadding;
  final double summaryVerticalPadding;
  final double summaryMinHeight;
  final double summaryDotSize;
  final double summarySpacing;
  final double summaryFontSize;
  final double detailEdgePadding;
  final double detailWidthFactor;
  final double detailMinWidth;
  final double detailMaxWidth;
  final double detailMaxHeight;
}

_PlaybackInsightFullscreenPolicy _resolvePlaybackInsightFullscreenPolicy(
  double width,
) {
  if (width >= 1600) {
    return const _PlaybackInsightFullscreenPolicy(
      summaryTopPadding: 104,
      summaryEndPadding: 36,
      summaryHorizontalPadding: 12,
      summaryVerticalPadding: 6,
      summaryMinHeight: 48,
      summaryDotSize: 8,
      summarySpacing: 8,
      summaryFontSize: 14,
      detailEdgePadding: 16,
      detailWidthFactor: 0.42,
      detailMinWidth: 320,
      detailMaxWidth: 440,
      detailMaxHeight: 360,
    );
  }
  if (width >= 840) {
    return const _PlaybackInsightFullscreenPolicy(
      summaryTopPadding: 92,
      summaryEndPadding: 28,
      summaryHorizontalPadding: 12,
      summaryVerticalPadding: 6,
      summaryMinHeight: 48,
      summaryDotSize: 8,
      summarySpacing: 8,
      summaryFontSize: 13,
      detailEdgePadding: 16,
      detailWidthFactor: 0.42,
      detailMinWidth: 320,
      detailMaxWidth: 440,
      detailMaxHeight: 360,
    );
  }
  if (width >= 600) {
    return const _PlaybackInsightFullscreenPolicy(
      summaryTopPadding: 86,
      summaryEndPadding: 26,
      summaryHorizontalPadding: 12,
      summaryVerticalPadding: 6,
      summaryMinHeight: 48,
      summaryDotSize: 8,
      summarySpacing: 8,
      summaryFontSize: 12,
      detailEdgePadding: 16,
      detailWidthFactor: 0.42,
      detailMinWidth: 320,
      detailMaxWidth: 440,
      detailMaxHeight: 360,
    );
  }
  return const _PlaybackInsightFullscreenPolicy(
    summaryTopPadding: 80,
    summaryEndPadding: 24,
    summaryHorizontalPadding: 12,
    summaryVerticalPadding: 6,
    summaryMinHeight: 48,
    summaryDotSize: 8,
    summarySpacing: 8,
    summaryFontSize: 12,
    detailEdgePadding: 16,
    detailWidthFactor: 0.42,
    detailMinWidth: 320,
    detailMaxWidth: 440,
    detailMaxHeight: 360,
  );
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
  const _StatusDot({required this.snapshot, this.size = 9});

  final PlaybackInsightSnapshot snapshot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = snapshot.lastError.isNotEmpty
        ? const Color(0xFFE57373)
        : snapshot.droppedFrames > 0 ||
              (snapshot.isBuffering && snapshot.playWhenReady)
        ? const Color(0xFFFFB74D)
        : const Color(0xFF66E28A);
    return Container(
      width: size,
      height: size,
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
