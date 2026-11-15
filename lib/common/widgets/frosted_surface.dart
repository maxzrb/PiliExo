import 'dart:ui' show ImageFilter;

import 'package:PiliPlus/models/common/frosted_surface_style.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

class FrostedSurfaceSettings {
  const FrostedSurfaceSettings({
    required this.enabled,
    required this.style,
    this.optimizeUniformBackground = true,
  });

  final bool enabled;
  final FrostedSurfaceStyle style;
  final bool optimizeUniformBackground;

  FrostedSurfaceSettings copyWith({
    bool? enabled,
    FrostedSurfaceStyle? style,
    bool? optimizeUniformBackground,
  }) => FrostedSurfaceSettings(
    enabled: enabled ?? this.enabled,
    style: style ?? this.style,
    optimizeUniformBackground:
        optimizeUniformBackground ?? this.optimizeUniformBackground,
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
    bool? optimizeUniformBackground,
  }) {
    final current = notifier.value;
    notifier.value = current.copyWith(
      enabled: enabled,
      style: style,
      optimizeUniformBackground: optimizeUniformBackground,
    );
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
    this.backgroundIsUniform = false,
  });

  final Widget child;
  final Color? color;
  final BorderRadius borderRadius;
  final double sigma;
  final bool showBorder;

  /// 仅在调用方确认背后为纯色且没有覆盖动态内容时使用。
  final bool backgroundIsUniform;

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
    final surfaceBrightness = ThemeData.estimateBrightnessForColor(
      opaqueSurface,
    );
    final themedChild = Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: settings.enabled
              ? Colors.transparent
              : opaqueSurface,
          // 按磨砂底色设置状态栏图标，避免透明 AppBar 被误判为深色背景。
          systemOverlayStyle:
              theme.appBarTheme.systemOverlayStyle ??
              SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarBrightness: surfaceBrightness,
                statusBarIconBrightness: surfaceBrightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light,
              ),
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

    final uniformOptimization =
        backgroundIsUniform && settings.optimizeUniformBackground;
    final surface = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        // 保留材质透明度、边框和裁剪，只省去纯色背景的重复模糊。
        enabled: !uniformOptimization,
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
    // 纯色背景不再依赖外部绘制，隔离顶栏，避免列表滚动时重复栅格化。
    return uniformOptimization ? RepaintBoundary(child: surface) : surface;
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
