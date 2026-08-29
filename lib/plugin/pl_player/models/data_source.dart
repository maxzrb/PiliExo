import 'package:PiliPlus/utils/path_utils.dart';
import 'package:path/path.dart' as path;

sealed class DataSource {
  final String videoSource;
  final String? audioSource;
  final int? videoBitrate;
  final int? audioBitrate;

  DataSource({
    required this.videoSource,
    required this.audioSource,
    this.videoBitrate,
    this.audioBitrate,
  });
}

class NetworkSource extends DataSource {
  NetworkSource({
    required super.videoSource,
    required super.audioSource,
    super.videoBitrate,
    super.audioBitrate,
  });
}

/// Media3 使用的单条 DASH fMP4 轨道。
///
/// URL 顺序由 Dart 侧按照当前 CDN 设置排列，原生侧会在请求失败时继续尝试
/// 后续地址，并从上次读取位置恢复 Range 请求。
class HdrTrackSource {
  final List<String> urls;
  final String? mimeType;
  final String? codecs;
  final int? width;
  final int? height;
  final String? frameRate;
  final int? bitrate;

  HdrTrackSource({
    required Iterable<String> urls,
    this.mimeType,
    this.codecs,
    this.width,
    this.height,
    this.frameRate,
    this.bitrate,
  }) : urls = urls.where((url) => url.isNotEmpty).toSet().toList() {
    if (this.urls.isEmpty) {
      throw ArgumentError('HDR 轨道至少需要一个 URL');
    }
  }

  Map<String, Object?> toJson() => {
    'urls': urls,
    if (mimeType != null) 'mimeType': mimeType,
    if (codecs != null) 'codecs': codecs,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (frameRate != null) 'frameRate': frameRate,
    if (bitrate != null) 'bitrate': bitrate,
  };
}

/// 在线 HDR 视频的完整播放源。
///
/// 该类型只由在线 UGC/PGC 播放页创建；直播、下载文件和普通 SDR 仍然使用
/// [NetworkSource] 或 [FileSource]，从而确保现有 mpv 路径不受影响。
class HdrNetworkSource extends NetworkSource {
  final int qualityCode;
  final HdrTrackSource video;
  final HdrTrackSource? audio;
  final Map<String, String> headers;

  HdrNetworkSource({
    required this.qualityCode,
    required this.video,
    this.audio,
    this.headers = const {},
  }) : super(
         videoSource: video.urls.first,
         audioSource: audio?.urls.first,
         videoBitrate: video.bitrate,
         audioBitrate: audio?.bitrate,
       );
}

/// HDR 后端选择规则，保持平台和播放类型判断集中在一个无副作用接口中。
abstract final class HdrPlaybackPolicy {
  static const supportedQualityCodes = {125, 126, 129};

  static bool shouldUseMedia3({
    required bool isAndroid,
    required bool isLive,
    required bool isFile,
    required bool enabled,
    required int qualityCode,
  }) =>
      isAndroid &&
      !isLive &&
      !isFile &&
      enabled &&
      supportedQualityCodes.contains(qualityCode);
}

class FileSource extends DataSource {
  final String dir;
  final bool isMp4;

  FileSource({
    required this.dir,
    required this.isMp4,
    required bool hasDashAudio,
    required String typeTag,
  }) : super(
         videoSource: path.join(
           dir,
           typeTag,
           isMp4 ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
         ),
         audioSource: isMp4 || !hasDashAudio
             ? null
             : path.join(dir, typeTag, PathUtils.audioNameType2),
       );
}
