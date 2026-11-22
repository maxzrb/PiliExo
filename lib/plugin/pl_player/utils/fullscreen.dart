import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:PiliPlus/utils/device_utils.dart';
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;

bool _isDesktopFullScreen = false;

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.EnterNativeFullscreen');
    } catch (_) {}
  }
}

@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (_isDesktopFullScreen) {
    _isDesktopFullScreen = false;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.ExitNativeFullscreen');
    } catch (_) {}
  }
}

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (DeviceUtils.isChromeOS) return null;

  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [.landscapeRight]);
}

bool? fullscreenViewportIsLandscape() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty || views.first.physicalSize.isEmpty) return null;
  final size = views.first.physicalSize;
  return size.width > size.height;
}

bool useFullscreenViewportLayout({
  required Size viewport,
  required bool fullscreen,
  required bool? targetLandscape,
}) {
  return fullscreen ||
      (targetLandscape != null &&
          !viewport.isEmpty &&
          (viewport.width > viewport.height) == targetLandscape);
}

/// 系统方法返回时，Flutter 视口可能还没有收到旋转后的尺寸。
Future<void> waitForFullscreenViewport(bool landscape) async {
  final binding = WidgetsBinding.instance;
  final ready = Completer<void>();
  void check() {
    if (!ready.isCompleted && fullscreenViewportIsLandscape() == landscape) {
      ready.complete();
    }
  }

  final observer = _FullscreenViewportObserver(check);
  binding.addObserver(observer);
  try {
    check();
    // 分屏和某些大屏策略会忽略旋转请求，按当前尺寸完成全屏。
    await ready.future.timeout(
      const Duration(milliseconds: 900),
      onTimeout: () {},
    );
  } finally {
    binding.removeObserver(observer);
  }
}

class _FullscreenViewportObserver with WidgetsBindingObserver {
  _FullscreenViewportObserver(this.check);
  final void Function() check;

  @override
  void didChangeMetrics() => check();
}

Future<void>? fullMode() {
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

bool _showSystemBar = true;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  _showSystemBar = false;
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

//退出全屏显示
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}
