import 'dart:ui' show SemanticsRole;

import 'package:flutter/widgets.dart';

class MainTabView extends StatefulWidget {
  const MainTabView({
    super.key,
    required this.index,
    required this.axis,
    required this.children,
    this.onSettled,
  });

  final int index;
  final Axis axis;
  final List<Widget> children;
  final ValueChanged<int>? onSettled;

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView>
    with SingleTickerProviderStateMixin {
  static const _atRest = AlwaysStoppedAnimation(Offset.zero);
  late final _visited = <int>{widget.index};
  final _positions = <int, Animation<Offset>>{};
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addStatusListener(_onStatus);
  late final _progress = _controller.drive(
    CurveTween(curve: Curves.easeOutQuart),
  );

  @override
  void didUpdateWidget(covariant MainTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;

    final currentPositions = {
      oldWidget.index: Offset.zero,
      for (final entry in _positions.entries) entry.key: entry.value.value,
    };
    _visited.add(widget.index);
    currentPositions.putIfAbsent(
      widget.index,
      () => _shift(widget.index > oldWidget.index ? 1 : -1),
    );
    _positions
      ..clear()
      ..addEntries(
        currentPositions.entries.map(
          (entry) => MapEntry(
            entry.key,
            Tween(
              begin: entry.value,
              end: entry.key == widget.index
                  ? Offset.zero
                  : _shift(entry.key < widget.index ? -1 : 1),
            ).animate(_progress),
          ),
        ),
      );
    _controller.forward(from: 0);
  }

  Offset _shift(double amount) =>
      widget.axis == Axis.horizontal ? Offset(amount, 0) : Offset(0, amount);

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final index = widget.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.index != index || _controller.isAnimating) {
        return;
      }
      setState(_positions.clear);
      _notifySettled(index);
    });
  }

  void _notifySettled(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.index == index && _positions.isEmpty) {
        widget.onSettled?.call(index);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = widget.axis == Axis.horizontal
        ? Directionality.of(context)
        : null;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final index in _visited) _tab(index, textDirection),
        ],
      ),
    );
  }

  Widget _tab(int index, TextDirection? textDirection) {
    final selected = index == widget.index;
    final position = _positions[index];
    final visible = selected || position != null;
    return Offstage(
      key: ValueKey(index),
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !selected,
          child: ExcludeFocus(
            excluding: !selected,
            child: SlideTransition(
              position: position ?? _atRest,
              textDirection: textDirection,
              child: RepaintBoundary(
                child: HeroMode(
                  enabled: selected,
                  child: Semantics(
                    role: SemanticsRole.tabPanel,
                    child: widget.children[index],
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
