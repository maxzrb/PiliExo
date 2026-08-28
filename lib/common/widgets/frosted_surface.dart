import 'dart:ui' show ImageFilter;

import 'package:PiliPlus/models/common/frosted_surface_style.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

class FrostedSurfaceSettings {
  const FrostedSurfaceSettings({
    required this.enabled,
    required this.style,
  });

  final bool enabled;
  final FrostedSurfaceStyle style;

  FrostedSurfaceSettings copyWith({
    bool? enabled,
    FrostedSurfaceStyle? style,
  }) => FrostedSurfaceSettings(
    enabled: enabled ?? this.enabled,
    style: style ?? this.style,
  );
}

abstract final class FrostedSurfaceConfig {
  static final ValueNotifier<FrostedSurfaceSettings> notifier = ValueNotifier(
    FrostedSurfaceSettings(
      enabled: Pref.enableFrostedSurface,
      style: Pref.frostedSurfaceStyle,
    ),
  );

  static void update({
    bool? enabled,
    FrostedSurfaceStyle? style,
  }) {
    final current = notifier.value;
    notifier.value = current.copyWith(enabled: enabled, style: style);
  }

  static void updateEnabled(bool enabled) => update(enabled: enabled);
}

/// 轻量毛玻璃材质，供主页顶栏、底栏和普通页面 AppBar 复用。
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.color,
    this.borderRadius = BorderRadius.zero,
    this.sigma = 18.0,
    this.showBorder = false,
  });

  final Widget child;
  final Color? color;
  final BorderRadius borderRadius;
  final double sigma;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FrostedSurfaceSettings>(
      valueListenable: FrostedSurfaceConfig.notifier,
      child: child,
      builder: (context, settings, child) => _buildSurface(
        context,
        settings,
        child!,
      ),
    );
  }

  Widget _buildSurface(
    BuildContext context,
    FrostedSurfaceSettings settings,
    Widget child,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = color == null || color!.a == 0
        ? colorScheme.surface
        : color!;
    final opaqueSurface = baseColor.withValues(alpha: 1);
    final themedChild = Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: settings.enabled
              ? Colors.transparent
              : opaqueSurface,
        ),
        navigationBarTheme: theme.navigationBarTheme.copyWith(
          backgroundColor: settings.enabled
              ? Colors.transparent
              : opaqueSurface,
          surfaceTintColor: settings.enabled
              ? Colors.transparent
              : theme.navigationBarTheme.surfaceTintColor,
        ),
        bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
          backgroundColor: settings.enabled
              ? Colors.transparent
              : opaqueSurface,
        ),
      ),
      child: child,
    );

    if (!settings.enabled) {
      return DecoratedBox(
        decoration: BoxDecoration(color: opaqueSurface),
        child: themedChild,
      );
    }

    final effectiveSigma = sigma == 18.0 ? settings.style.blurSigma : sigma;
    final backgroundColor = baseColor.withValues(
      alpha: settings.style.surfaceOpacity,
    );
    final borderColor = colorScheme.outline.withValues(alpha: 0.10);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effectiveSigma,
          sigmaY: effectiveSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            border: showBorder
                ? Border(
                    top: BorderSide(color: borderColor),
                  )
                : null,
          ),
          child: themedChild,
        ),
      ),
    );
  }
}

class FrostedPreferredSize extends StatelessWidget
    implements PreferredSizeWidget {
  const FrostedPreferredSize({
    super.key,
    required this.child,
  });

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => FrostedSurface(child: child);
}
