import 'package:PiliPlus/plugin/pl_player/models/playback_insight_mode.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// 让正在播放的视频页在设置变化后立即更新洞察摘要。
final ValueNotifier<PlaybackInsightMode> playbackInsightModeNotifier =
    ValueNotifier(Pref.playbackInsightMode);

Future<void> setPlaybackInsightMode(PlaybackInsightMode mode) async {
  playbackInsightModeNotifier.value = mode;
  await GStorage.setting.put(SettingBoxKey.playbackInsightMode, mode.index);
}
