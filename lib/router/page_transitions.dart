import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

import 'package:PiliPlus/router/predictive_back_transition.dart';
import 'package:PiliPlus/utils/device_utils.dart';

export 'package:PiliPlus/router/predictive_back_transition.dart'
    show PredictiveBackStyle;

abstract final class PageTransitions {
  // 旧版本曾把预测性返回放在页面过渡动画列表中，保留序号用于迁移。
  static const predictiveBackIndex = 17;
  static const predictiveBackLabel = '预测性返回';
  static const _minPredictiveBackSdk = 34;

  static final _predictiveBack = ValueNotifier(false);
  static final _predictiveBackStyle = ValueNotifier(
    defaultPredictiveBackStyle,
  );
  static final _predictiveBackSlidePercent = ValueNotifier(
    defaultPredictiveBackSlidePercent,
  );
  static final _predictiveBackFadePercent = ValueNotifier(
    defaultPredictiveBackStyle.defaultFadePercent,
  );
  static final _predictiveBackScalePercent = ValueNotifier(
    defaultPredictiveBackScalePercent,
  );

  static bool supportsPredictiveBack({int? androidSdkInt}) =>
      defaultTargetPlatform == TargetPlatform.android &&
      (androidSdkInt ?? (Platform.isAndroid ? DeviceUtils.sdkInt : 0)) >=
          _minPredictiveBackSdk;

  static ValueListenable<bool> get predictiveBack => _predictiveBack;
  static ValueListenable<PredictiveBackStyle> get predictiveBackStyle =>
      _predictiveBackStyle;
  static ValueListenable<int> get predictiveBackSlidePercent =>
      _predictiveBackSlidePercent;
  static ValueListenable<int> get predictiveBackFadePercent =>
      _predictiveBackFadePercent;
  static ValueListenable<int> get predictiveBackScalePercent =>
      _predictiveBackScalePercent;

  static String label(int index) => _getTransition(index).name;

  static String styleLabel(int index) =>
      PredictiveBackStyle.fromIndex(index).label;

  static Transition _getTransition(int index) => index == predictiveBackIndex
      ? Transition.native
      : Transition.values.asMap()[index] ?? Transition.native;

  static void select(int index) {
    Get.rootController.defaultTransition = _getTransition(index);
  }

  static void setEnabled(bool enabled, {int? androidSdkInt}) {
    _predictiveBack.value =
        enabled && supportsPredictiveBack(androidSdkInt: androidSdkInt);
  }

  static void selectStyleIndex(int index) {
    _predictiveBackStyle.value = PredictiveBackStyle.fromIndex(index);
  }

  static void selectMotion({
    int? slidePercent,
    int? fadePercent,
    int? scalePercent,
  }) {
    if (slidePercent != null) {
      _predictiveBackSlidePercent.value = slidePercent.clamp(20, 100);
    }
    if (fadePercent != null) {
      _predictiveBackFadePercent.value = fadePercent.clamp(0, 100);
    }
    if (scalePercent != null) {
      _predictiveBackScalePercent.value = scalePercent.clamp(0, 40);
    }
  }
}

mixin PredictiveBackPageRoute<T> on PageRoute<T> {
  @override
  bool get popGestureEnabled =>
      super.popGestureEnabled &&
      (!PageTransitions.predictiveBack.value ||
          !SmartDialog.checkExist(
            dialogTypes: const {
              SmartAllDialogType.custom,
              SmartAllDialogType.attach,
              SmartAllDialogType.loading,
              SmartAllDialogType.notify,
            },
          ));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => buildWithPredictiveBack(context, animation, secondaryAnimation, child, (
    context,
    child,
  ) {
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  });

  Widget buildWithPredictiveBack(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
    Widget Function(BuildContext, Widget) fallback,
  ) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return fallback(context, child);
    }
    return ValueListenableBuilder(
      valueListenable: PageTransitions.predictiveBack,
      child: child,
      builder: (context, enabled, child) {
        if (!enabled) return fallback(context, child!);
        return ValueListenableBuilder<PredictiveBackStyle>(
          valueListenable: PageTransitions.predictiveBackStyle,
          child: child,
          builder: (context, style, child) => ValueListenableBuilder<int>(
            valueListenable: PageTransitions.predictiveBackSlidePercent,
            child: child,
            builder: (context, slidePercent, child) =>
                ValueListenableBuilder<int>(
                  valueListenable: PageTransitions.predictiveBackFadePercent,
                  child: child,
                  builder: (context, fadePercent, child) =>
                      ValueListenableBuilder<int>(
                        valueListenable:
                            PageTransitions.predictiveBackScalePercent,
                        child: child,
                        builder: (context, scalePercent, child) =>
                            AppPredictiveBackPageTransitionsBuilder(
                              style: style,
                              slideFraction: slidePercent / 100,
                              fadeFraction: fadePercent / 100,
                              scaleFraction: scalePercent / 100,
                            ).buildTransitions(
                              this,
                              context,
                              animation,
                              secondaryAnimation,
                              child!,
                            ),
                      ),
                ),
          ),
        );
      },
    );
  }
}
