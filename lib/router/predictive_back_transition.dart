import 'dart:ui' show clampDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const defaultPredictiveBackStyle = PredictiveBackStyle.zoomFade;
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
  static PageRoute<dynamic>? _owner;

  static bool covers(PageRoute<dynamic> route) {
    final owner = _owner;
    return owner != null &&
        !identical(owner, route) &&
        owner.navigator == route.navigator;
  }

  static void begin(PageRoute<dynamic> owner, double routeProgress) {
    _owner = owner;
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
      builder:
          (
            context,
            phase,
            commitStartProgress,
            startBackEvent,
            currentBackEvent,
          ) {
            // popGestureInProgress 是整条 Navigator 的全局状态，被覆盖页同样
            // 为 true。这里只看本路由是否真的接手了手势，否则背景页会失去
            // 独立的层次效果。
            final showPredictive = phase != _PredictiveBackPhase.idle;
            if (!showPredictive) {
              return _PredictiveBackRouteSurface(
                route: route,
                animation: animation,
                coveredEffect: style.isSlide,
                child: child,
              );
            }
            return _PredictiveBackTransition(
              route: route,
              style: style,
              slideFraction: slideFraction,
              fadeFraction: fadeFraction,
              scaleFraction: scaleFraction,
              phase: phase,
              commitStartProgress: commitStartProgress,
              animation: animation,
              startBackEvent: startBackEvent,
              currentBackEvent: currentBackEvent,
              child: child,
            );
          },
    );
  }
}

typedef _PredictiveBackBuilder = Widget Function(
  BuildContext context,
  _PredictiveBackPhase phase,
  double commitStartProgress,
  PredictiveBackEvent? startBackEvent,
  PredictiveBackEvent? currentBackEvent,
);

enum _PredictiveBackPhase { idle, start, update, commit, cancel }

class _PredictiveBackGestureDetector extends StatefulWidget {
  const _PredictiveBackGestureDetector({
    required this.route,
    required this.builder,
  });

  final PageRoute<dynamic> route;
  final _PredictiveBackBuilder builder;

  @override
  State<_PredictiveBackGestureDetector> createState() =>
      _PredictiveBackGestureDetectorState();
}

class _PredictiveBackGestureDetectorState
    extends State<_PredictiveBackGestureDetector>
    with WidgetsBindingObserver {
  _PredictiveBackPhase _phase = _PredictiveBackPhase.idle;
  PredictiveBackEvent? _startBackEvent;
  PredictiveBackEvent? _currentBackEvent;
  double _commitStartProgress = 0;
  bool _gestureStarted = false;

  bool get _isEnabled =>
      widget.route.isCurrent && widget.route.popGestureEnabled;

  void _setPhase(_PredictiveBackPhase phase) {
    if (mounted && _phase != phase) {
      setState(() => _phase = phase);
    }
  }

  void _setEvents(
    PredictiveBackEvent? startBackEvent,
    PredictiveBackEvent? currentBackEvent,
  ) {
    if (!mounted) return;
    setState(() {
      _startBackEvent = startBackEvent;
      _currentBackEvent = currentBackEvent;
    });
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_isEnabled) return false;
    _setPhase(_PredictiveBackPhase.start);
    _gestureStarted = true;
    final routeProgress = 1 - backEvent.progress;
    PredictiveBackDriver.begin(widget.route, routeProgress);
    widget.route.handleStartBackGesture(progress: routeProgress);
    _setEvents(backEvent, backEvent);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_gestureStarted) return;
    _setPhase(_PredictiveBackPhase.update);
    final routeProgress = 1 - backEvent.progress;
    PredictiveBackDriver.update(
      widget.route,
      Curves.easeOutCubic.transform(routeProgress),
    );
    widget.route.handleUpdateBackGestureProgress(progress: routeProgress);
    _setEvents(_startBackEvent, backEvent);
  }

  @override
  void handleCancelBackGesture() {
    if (!_gestureStarted || _phase == _PredictiveBackPhase.idle) return;
    _gestureStarted = false;
    _setPhase(_PredictiveBackPhase.cancel);
    widget.route.handleCancelBackGesture();
    _setEvents(null, null);
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureStarted || _phase == _PredictiveBackPhase.idle) return;
    _gestureStarted = false;
    _setPhase(_PredictiveBackPhase.commit);
    _commitStartProgress = clampDouble(
      1 - widget.route.animation!.value,
      0,
      1,
    );
    widget.route.handleCommitBackGesture();
    _setEvents(null, null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var phase = _phase;
    if (!_gestureStarted && !widget.route.popGestureInProgress) {
      if (phase == _PredictiveBackPhase.start ||
          phase == _PredictiveBackPhase.update) {
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
      _startBackEvent,
      _currentBackEvent,
    );
  }
}

enum _ExitSide { left, right }

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
    required this.startBackEvent,
    required this.currentBackEvent,
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
  final PredictiveBackEvent? startBackEvent;
  final PredictiveBackEvent? currentBackEvent;
  final Widget child;

  @override
  State<_PredictiveBackTransition> createState() =>
      _PredictiveBackTransitionState();
}

class _PredictiveBackTransitionState extends State<_PredictiveBackTransition>
    with SingleTickerProviderStateMixin {
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
  late final Listenable _repaintListenable;
  _ExitSide _followSide = _ExitSide.right;

  _ExitSide get _exitSide {
    switch (widget.style) {
      case PredictiveBackStyle.followGesture:
        return _followSide;
      case PredictiveBackStyle.alwaysRight:
        return _ExitSide.right;
      case PredictiveBackStyle.alwaysLeft:
        return _ExitSide.left;
      case PredictiveBackStyle.fade:
      case PredictiveBackStyle.zoomFade:
        return _ExitSide.right;
    }
  }

  void _updateFollowSide() {
    if (widget.currentBackEvent?.swipeEdge case final swipeEdge?) {
      final side = swipeEdge == SwipeEdge.right
          ? _ExitSide.left
          : _ExitSide.right;
      if (side != _followSide) {
        _followSide = side;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _commitController = AnimationController(
      vsync: this,
    );
    _repaintListenable = Listenable.merge([
      widget.animation,
      _commitController,
    ]);
    _repaintListenable.addListener(_syncDriverProgress);
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
    _repaintListenable.removeListener(_syncDriverProgress);
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
    _updateFollowSide();
    final width = MediaQuery.widthOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final slideFraction = clampDouble(widget.slideFraction, 0.2, 1);
    final fadeFraction = clampDouble(widget.fadeFraction, 0, 1);
    final scaleFraction = clampDouble(widget.scaleFraction, 0, 0.4);
    final releaseEased = Curves.easeOutCubic.transform(
      clampDouble(widget.commitStartProgress, 0, 1),
    );
    return AnimatedBuilder(
      animation: _repaintListenable,
      child: widget.child,
      builder: (context, child) {
        final isCommit = widget.phase == _PredictiveBackPhase.commit;
        final commitProgress = isCommit ? _pageSettleProgress : 0.0;
        final rawProgress = isCommit
            ? widget.commitStartProgress +
                  (1 - widget.commitStartProgress) * commitProgress
            : _dragProgress;
        // 拖动阶段最多走到用户设定比例；松手后补完剩余距离并滑出整屏，
        // 避免路由销毁时页面仍留在屏内造成跳变。
        final distanceProgress = isCommit
            ? releaseEased + (1 - releaseEased) * commitProgress
            : Curves.easeOutCubic.transform(rawProgress);
        final exitFraction = isCommit
            ? slideFraction * releaseEased +
                  (1 - slideFraction * releaseEased) * commitProgress
            : slideFraction * distanceProgress;
        final dragOpacity = 1 - fadeFraction * rawProgress;
        // 平移样式最终会完全离开屏幕；渐隐样式需要把透明度收到 0，
        // 否则路由销毁时还会残留半透明页面。
        final fadeOpacity = isCommit && !widget.style.isSlide
            ? dragOpacity * (1 - commitProgress)
            : dragOpacity;
        final fadeChild = Opacity(
          key: const ValueKey('predictive-back-opacity'),
          opacity: fadeOpacity,
          child: child,
        );

        return switch (widget.style) {
          PredictiveBackStyle.fade => fadeChild,
          PredictiveBackStyle.zoomFade => Transform.scale(
            key: const ValueKey('predictive-back-scale'),
            scale: 1 - scaleFraction * distanceProgress,
            child: fadeChild,
          ),
          PredictiveBackStyle.followGesture ||
          PredictiveBackStyle.alwaysRight ||
          PredictiveBackStyle.alwaysLeft => Transform.translate(
            offset: Offset(
              _snapToPixel(
                (_exitSide == _ExitSide.right ? 1 : -1) * width * exitFraction,
                pixelRatio,
              ),
              0,
            ),
            child: fadeChild,
          ),
        };
      },
    );
  }

  double _snapToPixel(double value, double pixelRatio) =>
      (value * pixelRatio).roundToDouble() / pixelRatio;
}

/// 预测性返回开启时统一接管进入/退出与背景层，避免 Material Zoom 在
/// 手势刚开始时就把被覆盖页淡出，失去层次。
class _PredictiveBackRouteSurface extends StatelessWidget {
  const _PredictiveBackRouteSurface({
    required this.route,
    required this.animation,
    required this.coveredEffect,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final bool coveredEffect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.widthOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        animation,
        PredictiveBackDriver.active,
        PredictiveBackDriver.depth,
      ]),
      child: FadeTransition(opacity: animation, child: child),
      builder: (context, child) {
        final enter = clampDouble(animation.value, 0, 1);
        final enterEased = Curves.easeOutCubic.transform(enter);
        final result = Transform.scale(
          scale: 0.9 + 0.1 * enterEased,
          child: child,
        );
        if (!coveredEffect) return result;

        final depth = PredictiveBackDriver.covers(route)
            ? PredictiveBackDriver.depth.value
            : 0.0;
        final scale = 1 - 0.065 * depth;
        final offset =
            (width * 0.08 * depth * pixelRatio).roundToDouble() / pixelRatio;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Transform.translate(
              offset: Offset(-offset, 0),
              child: Transform.scale(
                key: const ValueKey('predictive-back-covered-scale'),
                scale: scale,
                child: result,
              ),
            ),
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
