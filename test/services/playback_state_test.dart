import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('piliexo-playback-');
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await GStorage.setting.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('系统媒体状态同步进度和倍速，关闭最后一个条目后恢复空闲', () {
    final handler = VideoPlayerServiceHandler()
      ..onVideoDetailChange(
        VideoDetailData(title: '测试视频', duration: 120),
        1,
        'test',
      );

    handler.onUpdateState(
      PlayerStatus.playing,
      false,
      false,
      position: const Duration(seconds: 15),
      speed: 1.5,
    );
    final playing = handler.playbackState.value;
    expect(playing.playing, isTrue);
    expect(playing.updatePosition, const Duration(seconds: 15));
    expect(playing.speed, 1.5);

    handler.onUpdateState(
      PlayerStatus.playing,
      false,
      false,
      position: const Duration(seconds: 15),
      speed: 1.5,
    );
    expect(identical(handler.playbackState.value, playing), isTrue);

    handler
      ..onVideoDetailChange(VideoDetailData(title: '临时视频'), 2, 'secondary')
      ..onVideoDetailDispose('secondary');
    expect(handler.mediaItem.value?.title, '测试视频');
    expect(handler.playbackState.value.processingState.name, 'ready');

    handler.onUpdateState(
      PlayerStatus.completed,
      false,
      false,
      position: const Duration(seconds: 120),
      speed: 1.5,
    );
    expect(handler.playbackState.value.playing, isFalse);

    handler
      ..onVideoDetailDispose('test')
      ..clearIfNeeded();
    expect(handler.playbackState.value.processingState.name, 'idle');
  });
}
