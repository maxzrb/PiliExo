/// 播放器洞察面板使用的实时快照。
///
/// 字段同时覆盖 Media3 HDR 和 mpv。某个后端没有提供的指标保持为空，
/// 面板只显示已经确认的数据，避免把推测值当成硬件或网络事实。
class PlaybackInsightSnapshot {
  const PlaybackInsightSnapshot({
    this.engine = '',
    this.quality = '',
    this.resolution = '',
    this.videoCodec = '',
    this.videoMimeType = '',
    this.videoColor = '',
    this.frameRate = '',
    this.videoDecoder = '',
    this.videoBitrate = '',
    this.audioCodec = '',
    this.audioMimeType = '',
    this.audioDecoder = '',
    this.audioBitrate = '',
    this.cdnHost = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.forwardBufferMs = 0,
    this.speed = 1.0,
    this.isPlaying = false,
    this.playWhenReady = false,
    this.isBuffering = false,
    this.firstFrame = false,
    this.droppedFrames = 0,
    this.lastError = '',
    this.lastEvent = '',
  });

  final String engine;
  final String quality;
  final String resolution;
  final String videoCodec;
  final String videoMimeType;
  final String videoColor;
  final String frameRate;
  final String videoDecoder;
  final String videoBitrate;
  final String audioCodec;
  final String audioMimeType;
  final String audioDecoder;
  final String audioBitrate;
  final String cdnHost;
  final int positionMs;
  final int durationMs;
  final int forwardBufferMs;
  final double speed;
  final bool isPlaying;
  final bool playWhenReady;
  final bool isBuffering;
  final bool firstFrame;
  final int droppedFrames;
  final String lastError;
  final String lastEvent;

  bool get hasMeasuredData =>
      resolution.isNotEmpty ||
      videoCodec.isNotEmpty ||
      videoMimeType.isNotEmpty ||
      videoDecoder.isNotEmpty ||
      audioCodec.isNotEmpty ||
      audioDecoder.isNotEmpty;

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
    if (droppedFrames > 0) return '已记录 $droppedFrames 个掉帧';
    if (isBuffering && playWhenReady) return '缓冲中';
    if (!hasMeasuredData) return '等待播放器数据';
    return '实时数据';
  }

  List<PlaybackInsightRow> get overviewRows => _rows([
    PlaybackInsightRow('播放器', engine),
    PlaybackInsightRow('画质', quality),
    PlaybackInsightRow('分辨率', resolution),
    PlaybackInsightRow('视频码率', videoBitrate),
    PlaybackInsightRow('音频码率', audioBitrate),
    PlaybackInsightRow('CDN', cdnHost),
    PlaybackInsightRow('前向缓冲', _formatMilliseconds(forwardBufferMs)),
  ]);

  List<PlaybackInsightRow> get videoRows => _rows([
    PlaybackInsightRow('视频编码', videoCodec),
    PlaybackInsightRow('媒体类型', videoMimeType),
    PlaybackInsightRow('色彩信息', videoColor),
    PlaybackInsightRow('帧率', frameRate),
    PlaybackInsightRow('视频码率', videoBitrate),
    PlaybackInsightRow('视频解码器', videoDecoder),
    PlaybackInsightRow('掉帧', '$droppedFrames'),
  ]);

  List<PlaybackInsightRow> get audioRows => _rows([
    PlaybackInsightRow('音频编码', audioCodec),
    PlaybackInsightRow('媒体类型', audioMimeType),
    PlaybackInsightRow('音频解码器', audioDecoder),
    PlaybackInsightRow('音频码率', audioBitrate),
  ]);

  List<PlaybackInsightRow> get runtimeRows => _rows([
    PlaybackInsightRow('播放状态', isPlaying ? '播放中' : '已暂停'),
    PlaybackInsightRow('准备播放', playWhenReady ? '是' : '否'),
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
