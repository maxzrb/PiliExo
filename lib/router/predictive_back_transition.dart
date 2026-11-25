import 'dart:ui' show clampDouble;

import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const defaultPredictiveBackStyle = PredictiveBackStyle.followGesture;
const defaultPredictiveBackSlidePercent = 70;
const defaultPredictiveBackScalePercent = 20;

enum PredictiveBackStyle {
  followGesture('跟手方向'),
  alwaysRight('向右返回'),
  alwaysLeft('向左返回'),
  fade('页面渐隐'),
  zoomFade('缩小渐隐');

  const PredictiveBackStyle(this.label);

  final String label;

  bool get isSlide =>
      this == followGesture || this == alwaysRight || this == alwaysLeft;

  /// 未单独调整过渐隐幅度时的默认值。滑动样式默认不渐隐；
  /// 渐隐样式若为 0 就完全看不出效果，因此默认完全淡出。
  int get defaultFadePercent => isSlide ? 0 : 100;

  static PredictiveBackStyle fromIndex(int index) =>
      index >= 0 && index < values.length
      ? values[index]
      : defaultPredictiveBackStyle;
}

/// 当前预测性返回的可见进度。Flutter 的 secondaryAnimation 在手势直接
/// 改写路由动画值时不会持续驱动被覆盖页，因此用独立进度驱动背景层。
abstract final class PredictiveBackDriver {
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static final ValueNotifier<double> depth = ValueNotifier(0);
  static final _exitSide = ValueNotifier(_ExitSide.right);
  static PageRoute<dynamic>? _owner;

  static bool covers(PageRoute<dynamic> route) {
    final owner = _owner;
    return owner != null &&
        !identical(owner, route) &&
        owner.navigator == route.navigator;
  }

  static void _begin(
    PageRoute<dynamic> owner,
    double routeProgress,
    _ExitSide exitSide,
  ) {
    _owner = owner;
    _exitSide.value = exitSide;
    depth.value = Curves.easeOutCubic.transform(routeProgress);
    active.value = true;
  }

  static void update(Object owner, double value) {
    if (!identical(_owner, owner)) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(_owner, owner)) depth.value = value;
      });
    } else {
      depth.value = value;
    }
  }

  static void end(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_owner == null) {
        active.value = false;
        depth.value = 0;
      }
    });
  }
}

class AppPredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPredictiveBackPageTransitionsBuilder({
    required this.style,
    required this.slideFraction,
    required this.fadeFraction,
    required this.scaleFraction,
  });

  final PredictiveBackStyle style;
  final double slideFraction;
  final double fadeFraction;
  final double scaleFraction;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PredictiveBackGestureDetector(
      route: route,
      style: style,
      builder: (context, phase, commitStartProgress, exitSide) =>
          _PredictiveBackTransition(
            route: route,
            style: style,
            slideFraction: slideFraction,
            fadeFraction: fadeFraction,
            scaleFraction: scaleFraction,
            phase: phase,
            commitStartProgress: commitStartProgress,
            animation: animation,
            exitSide: exitSide,
            child: child,
          ),
    );
  }
}

typedef _PredictiveBackBuilder = Widget Function(
  BuildContext context,
  _PredictiveBackPhase phase,
  double commitStartProgress,
  _ExitSide exitSide,
);

enum _PredictiveBackPhase { idle, preview, commit, cancel }

class _PredictiveBackGestureDetector extends StatefulWidget {
  const _PredictiveBackGestureDetector({
    required this.route,
    required this.style,
    required this.builder,
  });

  final PageRoute<dynamic> route;
  final PredictiveBackStyle style;
  final _PredictiveBackBuilder builder;

  @override
  State<_PredictiveBackGestureDetector> createState() =>
      _PredictiveBackGestureDetectorState();
}

class _PredictiveBackGestureDetectorState
    extends State<_PredictiveBackGestureDetector>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  _PredictiveBackPhase _phase = _PredictiveBackPhase.idle;
  _ExitSide _exitSide = _ExitSide.right;
  double _commitStartProgress = 0;
  bool _gestureStarted = false;
  Ticker? _previewFrames;

  bool get _isEnabled =>
      widget.route.isCurrent && widget.route.popGestureEnabled;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (_gestureStarted || backEvent.isButtonEvent || !_isEnabled) return false;
    setState(() {
      _phase = _PredictiveBackPhase.preview;
      _exitSide = _ExitSide.fromGesture(widget.style, backEvent.swipeEdge);
    });
    _gestureStarted = true;
    // 手势回调可能紧接在同一显示周期的 Flutter 帧之前到达。拖动期间
    // 保持下一帧已排队，让每次显示同步都能使用最新的手势进度。
    (_previewFrames ??= createTicker((_) {})).start();
    final routeProgress = 1 - backEvent.progress;
    PredictiveBackDriver._begin(widget.route, routeProgress, _exitSide);
    widget.route.handleStartBackGesture(progress: routeProgress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_gestureStarted) return;
    final routeProgress = 1 - backEvent.progress;
    PredictiveBackDriver.update(
      widget.route,
      Curves.easeOutCubic.transform(routeProgress),
    );
    // 路由动画已驱动页面绘制，手势进度不需要再触发一次状态更新。
    widget.route.handleUpdateBackGestureProgress(progress: routeProgress);
  }

  @override
  void handleCancelBackGesture() {
    if (!_gestureStarted) return;
    _gestureStarted = false;
    _previewFrames?.stop();
    setState(() => _phase = _PredictiveBackPhase.cancel);
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureStarted) return;
    _gestureStarted = false;
    _previewFrames?.stop();
    setState(() {
      _phase = _PredictiveBackPhase.commit;
      _commitStartProgress = clampDouble(
        1 - widget.route.animation!.value,
        0,
        1,
      );
    });
    widget.route.handleCommitBackGesture();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewFrames?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var phase = _phase;
    if (!_gestureStarted && !widget.route.popGestureInProgress) {
      if (phase == _PredictiveBackPhase.preview) {
        phase = _PredictiveBackPhase.idle;
      } else if (phase == _PredictiveBackPhase.cancel) {
        final animation = widget.route.animation;
        if (animation == null ||
            animation.status == AnimationStatus.completed) {
          phase = _PredictiveBackPhase.idle;
        }
      }
    }
    return widget.builder(
      context,
      phase,
      _commitStartProgress,
      _exitSide,
    );
  }
}

enum _ExitSide {
  left(-1),
  right(1);

  const _ExitSide(this.sign);

  final double sign;

  static _ExitSide fromGesture(PredictiveBackStyle style, SwipeEdge edge) =>
      switch (style) {
        PredictiveBackStyle.followGesture =>
          edge == SwipeEdge.right ? left : right,
        PredictiveBackStyle.alwaysLeft => left,
        _ => right,
      };
}

class _PredictiveBackTransition extends StatefulWidget {
  const _PredictiveBackTransition({
    required this.route,
    required this.style,
    required this.slideFraction,
    required this.fadeFraction,
    required this.scaleFraction,
    required this.phase,
    required this.commitStartProgress,
    required this.animation,
    required this.exitSide,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final PredictiveBackStyle style;
  final double slideFraction;
  final double fadeFraction;
  final double scaleFraction;
  final _PredictiveBackPhase phase;
  final double commitStartProgress;
  final Animation<double> animation;
  final _ExitSide exitSide;
  final Widget child;

  @override
  State<_PredictiveBackTransition> createState() =>
      _PredictiveBackTransitionState();
}

class _PredictiveBackTransitionState extends State<_PredictiveBackTransition>
    with SingleTickerProviderStateMixin {
  static const _backCornerRadius = 32.0;
  static const _pageSettleMs = 220;
  static const _backgroundSettleMs = 280;
  static final _backgroundSettle = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 75,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 25,
    ),
  ]);

  late final AnimationController _commitController;
  late final Listenable _motion;
  late final Listenable _repaint;

  @override
  void initState() {
    super.initState();
    _commitController = AnimationController(
      vsync: this,
    );
    _motion = Listenable.merge([widget.animation, _commitController]);
    _repaint = Listenable.merge([
      _motion,
      PredictiveBackDriver.active,
      PredictiveBackDriver.depth,
      PredictiveBackDriver._exitSide,
    ]);
    _motion.addListener(_syncDriverProgress);
    // 极快的手势可能在同一帧内走完 start 与 commit，此时状态直接
    // 以 commit 创建，需要在这里也启动补完动画。
    if (widget.phase == _PredictiveBackPhase.commit) {
      _startCommit();
    }
  }

  void _startCommit() {
    _commitController
      ..duration = Duration(
        milliseconds: widget.style.isSlide
            ? _backgroundSettleMs
            : _pageSettleMs,
      )
      ..forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _PredictiveBackTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == _PredictiveBackPhase.idle &&
        oldWidget.phase != _PredictiveBackPhase.idle) {
      PredictiveBackDriver.end(widget.route);
    }
    if (widget.phase == _PredictiveBackPhase.commit &&
        oldWidget.phase != _PredictiveBackPhase.commit) {
      _startCommit();
    } else if (widget.phase != _PredictiveBackPhase.commit &&
        oldWidget.phase == _PredictiveBackPhase.commit) {
      _commitController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _motion.removeListener(_syncDriverProgress);
    PredictiveBackDriver.end(widget.route);
    _commitController.dispose();
    super.dispose();
  }

  void _syncDriverProgress() {
    final depth = switch (widget.phase) {
      _PredictiveBackPhase.commit =>
        Curves.easeOutCubic.transform(1 - widget.commitStartProgress) *
            (1 - _backgroundSettle.transform(_commitController.value)),
      _PredictiveBackPhase.cancel => Curves.easeOutCubic.transform(
        1 - _dragProgress,
      ),
      _ => null,
    };
    if (depth == null) return;
    PredictiveBackDriver.update(widget.route, depth);
  }

  double get _dragProgress => clampDouble(1 - widget.animation.value, 0, 1);

  double get _pageSettleProgress => Curves.easeOutCubic.transform(
    clampDouble(
      _commitController.value *
          (widget.style.isSlide ? _backgroundSettleMs / _pageSettleMs : 1),
      0,
      1,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.widthOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final slideFraction = clampDouble(widget.slideFraction, 0.2, 1);
    final fadeFraction = clampDouble(widget.fadeFraction, 0, 1);
    final scaleFraction = clampDouble(widget.scaleFraction, 0, 0.4);
    final releaseEased = Curves.easeOutCubic.transform(
      widget.commitStartProgress,
    );
    final isSlide = widget.style.isSlide;
    return AnimatedBuilder(
      animation: isSlide ? _repaint : _motion,
      child: widget.child,
      builder: (context, child) {
        final idle = widget.phase == _PredictiveBackPhase.idle;
        final depth =
            idle && isSlide && PredictiveBackDriver.covers(widget.route)
            ? PredictiveBackDriver.depth.value
            : 0.0;
        double offset;
        double scale;
        double opacity;
        double cornerRadius;
        if (idle) {
          opacity = clampDouble(widget.animation.value, 0, 1);
          scale =
              (0.9 + 0.1 * Curves.easeOutCubic.transform(opacity)) *
              (1 - 0.065 * depth);
          final exitSign = PredictiveBackDriver._exitSide.value.sign;
          // 跟手方向下，背景从前景退出的一侧向中间归位。
          final backgroundSign =
              widget.style == PredictiveBackStyle.followGesture
              ? exitSign
              : -exitSign;
          offset = backgroundSign * width * 0.08 * depth;
          cornerRadius = _backCornerRadius * clampDouble(depth, 0, 1);
        } else {
          final isCommit = widget.phase == _PredictiveBackPhase.commit;
          final commitProgress = isCommit ? _pageSettleProgress : 0.0;
          final rawProgress = isCommit
              ? widget.commitStartProgress +
                    (1 - widget.commitStartProgress) * commitProgress
              : _dragProgress;
          final distanceProgress = isCommit
              ? releaseEased + (1 - releaseEased) * commitProgress
              : Curves.easeOutCubic.transform(rawProgress);
          final exitFraction = isCommit
              ? slideFraction * releaseEased +
                    (1 - slideFraction * releaseEased) * commitProgress
              : slideFraction * distanceProgress;
          offset = isSlide ? widget.exitSide.sign * width * exitFraction : 0;
          scale = widget.style == PredictiveBackStyle.zoomFade
              ? 1 - scaleFraction * distanceProgress
              : 1;
          cornerRadius = _backCornerRadius * distanceProgress;
          opacity = 1 - fadeFraction * rawProgress;
          if (isCommit && !isSlide) opacity *= 1 - commitProgress;
        }

        // 手势进入、取消或结束时保留同一层级，避免重新挂接页面子树。
        final page = Transform.translate(
          offset: Offset((offset * pixelRatio).roundToDouble() / pixelRatio, 0),
          child: Transform.scale(
            key: ValueKey(
              isSlide
                  ? 'predictive-back-covered-scale'
                  : 'predictive-back-scale',
            ),
            scale: scale,
            child: ClipRRect(
              key: const ValueKey('predictive-back-corners'),
              borderRadius: BorderRadius.circular(cornerRadius),
              clipBehavior: cornerRadius == 0 ? Clip.none : Clip.antiAlias,
              child: Opacity(
                key: const ValueKey('predictive-back-opacity'),
                opacity: opacity,
                child: child,
              ),
            ),
          ),
        );
        if (!isSlide) return page;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            // 背景页位移和圆角露出的区域保持不透明，遮住下面的旧合成层。
            if (depth != 0 && widget.route.opaque)
              Positioned.fill(
                child: ColoredBox(
                  key: const ValueKey('predictive-back-background'),
                  color: ThemeUtils.darkTheme.scaffoldBackgroundColor,
                ),
              ),
            page,
            if (depth > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: 0.2 * clampDouble(depth, 0, 1),
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
