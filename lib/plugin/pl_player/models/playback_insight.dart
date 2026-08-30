import 'package:PiliPlus/plugin/pl_player/models/playback_telemetry.dart';

/// 播放器洞察面板使用的实时快照。
///
/// 技术数据由 [PlaybackTelemetry] 统一提供，下面的播放状态字段由
/// PlPlayerController 在同一时刻合并，确保 Media3 和 mpv/media-kit 使用同一套界面。
class PlaybackInsightSnapshot extends PlaybackTelemetry {
  const PlaybackInsightSnapshot({
    super.engine,
    super.quality,
    super.representation,
    super.representationId,
    super.resolution,
    super.videoCodec,
    super.videoCodecString,
    super.videoProfile,
    super.videoLevel,
    super.dolbyVisionProfile,
    super.dolbyVisionLevel,
    super.hdrType,
    super.videoMimeType,
    super.videoColor,
    super.frameRate,
    super.videoDecoder,
    super.videoDecoderType,
    super.videoBitrate,
    super.audioCodec,
    super.audioCodecString,
    super.audioMimeType,
    super.audioSampleRate,
    super.audioChannelCount,
    super.audioChannelLayout,
    super.audioDecoder,
    super.audioDecoderType,
    super.audioBitrate,
    super.cdnHost,
    super.cdnUri,
    super.bandwidthEstimate,
    super.playerState,
    super.droppedFrames,
    super.recentDroppedFrames,
    super.fallbackReason,
    super.fallbackHistory,
    super.lastError,
    super.lastEvent,
    this.positionMs = 0,
    this.durationMs = 0,
    this.forwardBufferMs = 0,
    this.speed = 1.0,
    this.isPlaying = false,
    this.playWhenReady = false,
    this.isBuffering = false,
    this.firstFrame = false,
  });

  factory PlaybackInsightSnapshot.fromTelemetry(
    PlaybackTelemetry telemetry, {
    int positionMs = 0,
    int durationMs = 0,
    int forwardBufferMs = 0,
    double speed = 1.0,
    bool isPlaying = false,
    bool playWhenReady = false,
    bool isBuffering = false,
    bool firstFrame = false,
  }) => PlaybackInsightSnapshot(
    engine: telemetry.engine,
    quality: telemetry.quality,
    representation: telemetry.representation,
    representationId: telemetry.representationId,
    resolution: telemetry.resolution,
    videoCodec: telemetry.videoCodec,
    videoCodecString: telemetry.videoCodecString,
    videoProfile: telemetry.videoProfile,
    videoLevel: telemetry.videoLevel,
    dolbyVisionProfile: telemetry.dolbyVisionProfile,
    dolbyVisionLevel: telemetry.dolbyVisionLevel,
    hdrType: telemetry.hdrType,
    videoMimeType: telemetry.videoMimeType,
    videoColor: telemetry.videoColor,
    frameRate: telemetry.frameRate,
    videoDecoder: telemetry.videoDecoder,
    videoDecoderType: telemetry.videoDecoderType,
    videoBitrate: telemetry.videoBitrate,
    audioCodec: telemetry.audioCodec,
    audioCodecString: telemetry.audioCodecString,
    audioMimeType: telemetry.audioMimeType,
    audioSampleRate: telemetry.audioSampleRate,
    audioChannelCount: telemetry.audioChannelCount,
    audioChannelLayout: telemetry.audioChannelLayout,
    audioDecoder: telemetry.audioDecoder,
    audioDecoderType: telemetry.audioDecoderType,
    audioBitrate: telemetry.audioBitrate,
    cdnHost: telemetry.cdnHost,
    cdnUri: telemetry.cdnUri,
    bandwidthEstimate: telemetry.bandwidthEstimate,
    playerState: telemetry.playerState,
    droppedFrames: telemetry.droppedFrames,
    recentDroppedFrames: telemetry.recentDroppedFrames,
    fallbackReason: telemetry.fallbackReason,
    fallbackHistory: telemetry.fallbackHistory,
    lastError: telemetry.lastError,
    lastEvent: telemetry.lastEvent,
    positionMs: positionMs,
    durationMs: durationMs,
    forwardBufferMs: forwardBufferMs,
    speed: speed,
    isPlaying: isPlaying,
    playWhenReady: playWhenReady,
    isBuffering: isBuffering,
    firstFrame: firstFrame,
  );

  final int positionMs;
  final int durationMs;
  final int forwardBufferMs;
  final double speed;
  final bool isPlaying;
  final bool playWhenReady;
  final bool isBuffering;
  final bool firstFrame;

  bool get hasMeasuredData =>
      resolution.isNotEmpty ||
      videoCodec.isNotEmpty ||
      videoMimeType.isNotEmpty ||
      videoDecoder.isNotEmpty ||
      videoBitrate.isNotEmpty ||
      audioCodec.isNotEmpty ||
      audioDecoder.isNotEmpty ||
      audioBitrate.isNotEmpty;

  String get summary {
    final parts = [
      if (resolution.isNotEmpty) resolution,
      if (videoCodec.isNotEmpty) videoCodec,
      if (frameRate.isNotEmpty) frameRate,
    ];
    final summary = parts.take(3).join(' · ');
    return summary.isEmpty ? (engine.isNotEmpty ? engine : '等待播放器数据') : summary;
  }

  String get statusText {
    if (lastError.isNotEmpty) return '播放出现错误';
    if (fallbackReason.isNotEmpty) return '已执行编码回退';
    if (droppedFrames > 0) return '已记录 $droppedFrames 个掉帧';
    if (isBuffering && playWhenReady) return '缓冲中';
    if (!hasMeasuredData) return '等待播放器数据';
    return '实时数据';
  }

  List<PlaybackInsightRow> get overviewRows => _rows([
    PlaybackInsightRow('播放器', engine),
    PlaybackInsightRow('画质', quality),
    PlaybackInsightRow('分辨率', resolution),
    PlaybackInsightRow('视频 Codec', videoCodec),
    PlaybackInsightRow('HDR 类型', hdrType),
    PlaybackInsightRow('视频码率', videoBitrate),
    PlaybackInsightRow('音频码率', audioBitrate),
    PlaybackInsightRow('CDN / Host', cdnHost),
    PlaybackInsightRow('前向缓冲', _formatMilliseconds(forwardBufferMs)),
    PlaybackInsightRow('带宽估计', bandwidthEstimate),
  ]);

  List<PlaybackInsightRow> get videoRows => _rows([
    PlaybackInsightRow('视频 Codec', videoCodec),
    PlaybackInsightRow('Codec String', videoCodecString),
    PlaybackInsightRow('Profile', videoProfile),
    PlaybackInsightRow('Level', videoLevel),
    PlaybackInsightRow('Dolby Vision Profile', dolbyVisionProfile),
    PlaybackInsightRow('Dolby Vision Level', dolbyVisionLevel),
    PlaybackInsightRow('HDR 类型', hdrType),
    PlaybackInsightRow('媒体类型', videoMimeType),
    PlaybackInsightRow('色彩信息', videoColor),
    PlaybackInsightRow('分辨率', resolution),
    PlaybackInsightRow('帧率', frameRate),
    PlaybackInsightRow('视频码率', videoBitrate),
    PlaybackInsightRow('视频解码器', videoDecoder),
    PlaybackInsightRow('硬/软解', videoDecoderType),
    PlaybackInsightRow('累计掉帧', '$droppedFrames'),
    PlaybackInsightRow('近期掉帧', '$recentDroppedFrames'),
  ]);

  List<PlaybackInsightRow> get audioRows => _rows([
    PlaybackInsightRow('音频 Codec', audioCodec),
    PlaybackInsightRow('Codec String', audioCodecString),
    PlaybackInsightRow('媒体类型', audioMimeType),
    PlaybackInsightRow('采样率', audioSampleRate),
    PlaybackInsightRow('声道数', audioChannelCount),
    PlaybackInsightRow('声道布局', audioChannelLayout),
    PlaybackInsightRow('音频解码器', audioDecoder),
    PlaybackInsightRow('硬/软解', audioDecoderType),
    PlaybackInsightRow('音频码率', audioBitrate),
  ]);

  List<PlaybackInsightRow> get runtimeRows => _rows([
    PlaybackInsightRow(
      '播放器状态',
      playerState.isNotEmpty ? playerState : (isPlaying ? '播放中' : '已暂停'),
    ),
    PlaybackInsightRow('准备播放', playWhenReady ? '是' : '否'),
    PlaybackInsightRow('缓冲状态', isBuffering ? '缓冲中' : '已就绪'),
    PlaybackInsightRow('首帧', firstFrame ? '已渲染' : '未渲染'),
    PlaybackInsightRow(
      '进度',
      '${_formatMilliseconds(positionMs)} / ${_formatMilliseconds(durationMs)}',
    ),
    PlaybackInsightRow('倍速', '${speed.toStringAsFixed(2)}x'),
  ]);

  List<PlaybackInsightRow> get eventRows => _rows([
    PlaybackInsightRow('最近事件', lastEvent),
    PlaybackInsightRow('最近错误', lastError),
    PlaybackInsightRow('最近回退原因', fallbackReason),
  ]);

  List<PlaybackInsightRow> get fallbackRows => _rows([
    PlaybackInsightRow(
      '回退历史',
      fallbackHistory.map((item) => item.display).join('\n'),
    ),
  ]);

  static List<PlaybackInsightRow> _rows(List<PlaybackInsightRow> rows) =>
      rows.where((row) => row.value.isNotEmpty).toList(growable: false);

  static String _formatMilliseconds(int milliseconds) {
    if (milliseconds <= 0) return '0:00';
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class PlaybackInsightRow {
  const PlaybackInsightRow(this.label, this.value);

  final String label;
  final String value;
}
