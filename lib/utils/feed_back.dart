import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';

bool enableFeedback = Pref.feedBackEnable;
int feedbackStrength = Pref.feedBackStrength;

const _hapticChannel = MethodChannel('com.example.piliplus/haptics');

void feedBack() {
  if (!enableFeedback) {
    return;
  }

  final strength = feedbackStrength.clamp(1, 255).toInt();
  if (Platform.isAndroid) {
    // Android 原生通道使用真实振幅，避免 light/medium/heavy 受机型映射影响。
    unawaited(_vibrateAndroid(strength));
  } else if (strength < 86) {
    HapticFeedback.lightImpact();
  } else if (strength < 171) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.heavyImpact();
  }
}

Future<void> _vibrateAndroid(int strength) async {
  try {
    await _hapticChannel.invokeMethod<void>('vibrate', {
      'amplitude': strength,
      'durationMs': 18,
    });
  } catch (_) {
    // 旧设备或非 Android 测试环境没有原生通道时保持静默，不影响导航。
  }
}
