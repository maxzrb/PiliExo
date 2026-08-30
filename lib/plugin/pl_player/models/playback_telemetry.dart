/// 播放器诊断数据层。
///
/// 该模型只保存播放器已经报告的事实，不根据 codec 名称推断设备能力。
/// Media3 和 mpv/media-kit 都将实际可用的数据映射到这里，再由洞察界面展示。
class PlaybackTelemetry {
  const PlaybackTelemetry({
    this.engine = '',
    this.quality = '',
    this.representation = '',
    this.representationId = '',
    this.resolution = '',
    this.videoCodec = '',
    this.videoCodecString = '',
    this.videoProfile = '',
    this.videoLevel = '',
    this.dolbyVisionProfile = '',
    this.dolbyVisionLevel = '',
    this.hdrType = '',
    this.videoMimeType = '',
    this.videoColor = '',
    this.frameRate = '',
    this.videoDecoder = '',
    this.videoDecoderType = '',
    this.videoBitrate = '',
    this.audioCodec = '',
    this.audioCodecString = '',
    this.audioMimeType = '',
    this.audioSampleRate = '',
    this.audioChannelCount = '',
    this.audioChannelLayout = '',
    this.audioDecoder = '',
    this.audioDecoderType = '',
    this.audioBitrate = '',
    this.cdnHost = '',
    this.cdnUri = '',
    this.bandwidthEstimate = '',
    this.playerState = '',
    this.droppedFrames = 0,
    this.recentDroppedFrames = 0,
    this.fallbackReason = '',
    this.fallbackHistory = const <PlaybackFallbackRecord>[],
    this.lastError = '',
    this.lastEvent = '',
  });

  final String engine;
  final String quality;
  final String representation;
  final String representationId;
  final String resolution;
  final String videoCodec;
  final String videoCodecString;
  final String videoProfile;
  final String videoLevel;
  final String dolbyVisionProfile;
  final String dolbyVisionLevel;
  final String hdrType;
  final String videoMimeType;
  final String videoColor;
  final String frameRate;
  final String videoDecoder;
  final String videoDecoderType;
  final String videoBitrate;
  final String audioCodec;
  final String audioCodecString;
  final String audioMimeType;
  final String audioSampleRate;
  final String audioChannelCount;
  final String audioChannelLayout;
  final String audioDecoder;
  final String audioDecoderType;
  final String audioBitrate;
  final String cdnHost;
  final String cdnUri;
  final String bandwidthEstimate;
  final String playerState;
  final int droppedFrames;
  final int recentDroppedFrames;
  final String fallbackReason;
  final List<PlaybackFallbackRecord> fallbackHistory;
  final String lastError;
  final String lastEvent;

  PlaybackTelemetry copyWith({
    String? engine,
    String? quality,
    String? representation,
    String? representationId,
    String? resolution,
    String? videoCodec,
    String? videoCodecString,
    String? videoProfile,
    String? videoLevel,
    String? dolbyVisionProfile,
    String? dolbyVisionLevel,
    String? hdrType,
    String? videoMimeType,
    String? videoColor,
    String? frameRate,
    String? videoDecoder,
    String? videoDecoderType,
    String? videoBitrate,
    String? audioCodec,
    String? audioCodecString,
    String? audioMimeType,
    String? audioSampleRate,
    String? audioChannelCount,
    String? audioChannelLayout,
    String? audioDecoder,
    String? audioDecoderType,
    String? audioBitrate,
    String? cdnHost,
    String? cdnUri,
    String? bandwidthEstimate,
    String? playerState,
    int? droppedFrames,
    int? recentDroppedFrames,
    String? fallbackReason,
    List<PlaybackFallbackRecord>? fallbackHistory,
    String? lastError,
    String? lastEvent,
  }) => PlaybackTelemetry(
    engine: engine ?? this.engine,
    quality: quality ?? this.quality,
    representation: representation ?? this.representation,
    representationId: representationId ?? this.representationId,
    resolution: resolution ?? this.resolution,
    videoCodec: videoCodec ?? this.videoCodec,
    videoCodecString: videoCodecString ?? this.videoCodecString,
    videoProfile: videoProfile ?? this.videoProfile,
    videoLevel: videoLevel ?? this.videoLevel,
    dolbyVisionProfile: dolbyVisionProfile ?? this.dolbyVisionProfile,
    dolbyVisionLevel: dolbyVisionLevel ?? this.dolbyVisionLevel,
    hdrType: hdrType ?? this.hdrType,
    videoMimeType: videoMimeType ?? this.videoMimeType,
    videoColor: videoColor ?? this.videoColor,
    frameRate: frameRate ?? this.frameRate,
    videoDecoder: videoDecoder ?? this.videoDecoder,
    videoDecoderType: videoDecoderType ?? this.videoDecoderType,
    videoBitrate: videoBitrate ?? this.videoBitrate,
    audioCodec: audioCodec ?? this.audioCodec,
    audioCodecString: audioCodecString ?? this.audioCodecString,
    audioMimeType: audioMimeType ?? this.audioMimeType,
    audioSampleRate: audioSampleRate ?? this.audioSampleRate,
    audioChannelCount: audioChannelCount ?? this.audioChannelCount,
    audioChannelLayout: audioChannelLayout ?? this.audioChannelLayout,
    audioDecoder: audioDecoder ?? this.audioDecoder,
    audioDecoderType: audioDecoderType ?? this.audioDecoderType,
    audioBitrate: audioBitrate ?? this.audioBitrate,
    cdnHost: cdnHost ?? this.cdnHost,
    cdnUri: cdnUri ?? this.cdnUri,
    bandwidthEstimate: bandwidthEstimate ?? this.bandwidthEstimate,
    playerState: playerState ?? this.playerState,
    droppedFrames: droppedFrames ?? this.droppedFrames,
    recentDroppedFrames: recentDroppedFrames ?? this.recentDroppedFrames,
    fallbackReason: fallbackReason ?? this.fallbackReason,
    fallbackHistory: fallbackHistory ?? this.fallbackHistory,
    lastError: lastError ?? this.lastError,
    lastEvent: lastEvent ?? this.lastEvent,
  );
}

/// 一次 Representation fallback 的可读记录。
class PlaybackFallbackRecord {
  const PlaybackFallbackRecord({
    this.from = '',
    this.to = '',
    this.reason = '',
    this.errorCode = '',
    this.message = '',
  });

  final String from;
  final String to;
  final String reason;
  final String errorCode;
  final String message;

  String get display {
    final route = to.isEmpty ? '$from → 无可用候选' : '$from → $to';
    final detail = [
      if (errorCode.isNotEmpty) errorCode,
      if (reason.isNotEmpty) reason,
      if (message.isNotEmpty) message,
    ].join(': ');
    return detail.isEmpty ? route : '$route（$detail）';
  }
}
