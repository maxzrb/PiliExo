import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight.dart';
import 'package:PiliPlus/plugin/pl_player/models/playback_insight_mode.dart';
import 'package:PiliPlus/plugin/pl_player/utils/playback_insight_settings.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/playback_insight.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late PlPlayerController controller;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'piliexo-playback-insight-test-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.video = await Hive.openBox('video');
    controller = PlPlayerController.getInstance();
  });

  tearDownAll(() async {
    controller.playerStatus.value = .paused;
    controller.dispose();
    await GStorage.video.close();
    await GStorage.localCache.close();
    await GStorage.setting.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('播放器洞察视频详情包含视频码率', () {
    const snapshot = PlaybackInsightSnapshot(
      videoBitrate: '5.00 Mbps',
      audioBitrate: '192 kbps',
    );

    expect(
      snapshot.videoRows.any(
        (row) => row.label == '视频码率' && row.value == '5.00 Mbps',
      ),
      isTrue,
    );
    expect(
      snapshot.overviewRows.any(
        (row) => row.label == '视频码率' && row.value == '5.00 Mbps',
      ),
      isTrue,
    );
    expect(
      snapshot.audioRows.any(
        (row) => row.label == '音频码率' && row.value == '192 kbps',
      ),
      isTrue,
    );
  });

  test('DASH 轨道码率会传入播放器数据源作为回退值', () {
    final source = HdrNetworkSource(
      qualityCode: 125,
      video: HdrTrackSource(
        urls: ['https://example.com/video.m4s'],
        bitrate: 5000000,
      ),
      audio: HdrTrackSource(
        urls: ['https://example.com/audio.m4s'],
        bitrate: 192000,
      ),
    );

    expect(source.videoBitrate, 5000000);
    expect(source.audioBitrate, 192000);
    expect(source.video.toJson()['bitrate'], 5000000);

    final fallbackSource = NetworkSource(
      videoSource: 'https://example.com/video.mp4',
      audioSource: null,
      videoBitrate: 5000000,
    );
    expect(fallbackSource.videoBitrate, 5000000);
  });

  for (final mode in [PlaybackInsightMode.off, PlaybackInsightMode.smart]) {
    testWidgets('$mode隐藏时快照不产生UI帧，重新显示读取最新数据', (tester) async {
      playbackInsightModeNotifier.value = mode;
      controller.showControls.value = false;
      controller.playbackInsight.value = const PlaybackInsightSnapshot(
        resolution: '1920×1080',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 200,
            child: PlaybackInsightHud(
              controller: controller,
              isFullScreen: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('1920×1080'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);

      controller.playbackInsight.value = const PlaybackInsightSnapshot(
        resolution: '1280×720',
      );
      expect(tester.binding.hasScheduledFrame, isFalse);

      playbackInsightModeNotifier.value = PlaybackInsightMode.always;
      await tester.pumpAndSettle();
      expect(find.text('1280×720'), findsOneWidget);
    });
  }

  testWidgets('智能HUD隐藏期间的新掉帧仍会弹出提示，普通更新不延长提示', (tester) async {
    playbackInsightModeNotifier.value = PlaybackInsightMode.smart;
    controller.showControls.value = false;
    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 200,
          child: PlaybackInsightHud(
            controller: controller,
            isFullScreen: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('1920×1080'), findsNothing);

    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
      droppedFrames: 3,
      recentDroppedFrames: 3,
    );
    await tester.pumpAndSettle();
    expect(find.text('1920×1080'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
      droppedFrames: 3,
      positionMs: 9000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('1920×1080'), findsNothing);
  });

  testWidgets('隐藏HUD不提示起播三帧，确认的稳定异常仍能弹出', (tester) async {
    playbackInsightModeNotifier.value = PlaybackInsightMode.smart;
    controller.showControls.value = false;
    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 200,
          child: PlaybackInsightHud(
            controller: controller,
            isFullScreen: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    const excluded = PlaybackInsightSnapshot(
      resolution: '1920×1080',
      excludedDroppedFrames: 3,
    );
    expect(excluded.rawDroppedFrames, 3);
    expect(excluded.statusText, '实时数据');
    controller.playbackInsight.value = excluded;
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump();
    expect(find.text('1920×1080'), findsNothing);

    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
      droppedFrames: 3,
      recentDroppedFrames: 3,
    );
    await tester.pumpAndSettle();
    expect(find.text('1920×1080'), findsOneWidget);
  });

  test('历史异常保留详情计数，恢复后状态不再持续报掉帧', () {
    const recovered = PlaybackInsightSnapshot(
      resolution: '1920×1080',
      droppedFrames: 10,
      excludedDroppedFrames: 3,
    );
    expect(recovered.statusText, '实时数据');
    expect(recovered.rawDroppedFrames, 13);
  });

  testWidgets('摘要黑色背景区域可以点击展开详情', (tester) async {
    playbackInsightModeNotifier.value = PlaybackInsightMode.always;
    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 200,
            child: PlaybackInsightHud(
              controller: controller,
              isFullScreen: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 点击摘要右侧的留白，而不是文本本身，验证整个黑色 surface 都可点击。
    await tester.tapAt(const Offset(304, 62));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('播放器洞察'), findsOneWidget);
  });

  testWidgets('智能摘要渐隐期间仍可以点击展开详情', (tester) async {
    playbackInsightModeNotifier.value = PlaybackInsightMode.smart;
    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 200,
            child: PlaybackInsightHud(
              controller: controller,
              isFullScreen: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // 自动摘要刚开始渐隐时，点击仍应被摘要层接收。
    await tester.tapAt(const Offset(304, 62));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('播放器洞察'), findsOneWidget);
  });

  testWidgets('控制条隐藏后关闭详情不会闪出摘要', (tester) async {
    playbackInsightModeNotifier.value = PlaybackInsightMode.smart;
    controller.showControls.value = true;
    controller.playbackInsight.value = const PlaybackInsightSnapshot(
      resolution: '1920×1080',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 200,
            child: PlaybackInsightHud(
              controller: controller,
              isFullScreen: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(304, 62));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('播放器洞察'), findsOneWidget);

    controller.showControls.value = false;
    await tester.pump();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();

    expect(find.text('播放器洞察'), findsNothing);
    expect(find.text('1920×1080'), findsNothing);
  });
}
