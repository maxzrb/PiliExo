import 'package:collection/collection.dart';
import 'package:PiliPlus/utils/audio_track_selector.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/video/play/url.dart'
    show AudioItem, VideoItem, FormatItem;
import 'package:PiliPlus/models_new/live/live_room_play_info/codec.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

abstract final class VideoUtils {
  static CDNService cdnService = Pref.defaultCDNService;
  static String? liveCdnUrl = Pref.liveCdnUrl;
  static bool disableAudioCDN = Pref.disableAudioCDN;

  static const _proxyTf = 'proxy-tf-all-ws.bilivideo.com';

  static final _mirrorRegex = RegExp(
    r'^https?://(?:upos-\w+-(?!302)\w+|(?:upos|proxy)-tf-[^/]+)\.(?:bilivideo|akamaized)\.(?:com|net)/upgcxcode',
  );

  static final _mCdnTfRegex = RegExp(
    r'^https?://(?:(?:(?:\d{1,3}\.){3}\d{1,3}|[^/]+\.mcdn\.bilivideo\.(?:com|cn|net))(?:\:\d{1,5})?/v\d/resource)',
  );

  static String getCdnUrl(
    Iterable<String> urls, {
    CDNService? defaultCDNService,
    bool isAudio = false,
  }) {
    defaultCDNService ??= cdnService;

    if (defaultCDNService == CDNService.baseUrl) {
      return urls.first;
    }

    if (defaultCDNService == CDNService.akamai &&
        !(isAudio && disableAudioCDN)) {
      // Akamai签名绑定原地址，必须保留接口提供的完整URL及编码查询串。
      return urls.firstWhere(
        (url) => Uri.tryParse(url)?.host == CDNService.akamai.host,
        orElse: () => urls.first,
      );
    }

    String? mcdnTf;
    String? mcdnUpgcxcode;

    String last = '';
    for (final url in urls) {
      last = url;
      if (_mirrorRegex.hasMatch(url)) {
        final uri = Uri.parse(url);
        if (uri.queryParameters['os'] == 'mcdn') {
          // upos-sz-mirrorcoso1.bilivideo.com os=mcdn
          mcdnUpgcxcode = url;
        } else {
          if (defaultCDNService == CDNService.backupUrl ||
              (isAudio && disableAudioCDN)) {
            return url;
          }
          return uri.replace(host: defaultCDNService.host).toString();
        }
      }

      if (_mCdnTfRegex.hasMatch(url)) {
        mcdnTf = url;
        continue;
      }

      // upos-\w*-302.* & bcache & mcdn host but upgcxcode path
      if (url.contains('/upgcxcode/')) {
        mcdnUpgcxcode = url;
        continue;
      }

      // may be deprecated
      if (url.contains('szbdyd.com')) {
        final uri = Uri.parse(url);
        final hostname =
            uri.queryParameters['xy_usource'] ?? defaultCDNService.host;
        return uri
            .replace(scheme: 'https', host: hostname, port: 443)
            .toString();
      }

      if (kDebugMode) {
        debugPrint('unknown cdn type: $url');
      }
    }

    return mcdnUpgcxcode == null
        ? mcdnTf == null
              ? last
              : Uri(
                  scheme: 'https',
                  host: _proxyTf,
                  queryParameters: {'url': mcdnTf},
                ).toString()
        : Uri.parse(mcdnUpgcxcode)
              .replace(host: defaultCDNService.host ?? CDNService.ali.host)
              .toString();
  }

  /// 返回按当前 CDN 设置排序的完整候选 URL 列表。
  ///
  /// 普通 mpv 播放仍只取 [getCdnUrl] 的首个结果；Media3 需要保留所有备用
  /// 地址，以便在 403、5xx 或读取中断时从相同字节位置续传。
  static List<String> getCdnUrls(
    Iterable<String> urls, {
    CDNService? defaultCDNService,
    bool isAudio = false,
  }) {
    final source = urls.where((url) => url.isNotEmpty).toList();
    if (source.isEmpty) return const [];
    final result = <String>[
      getCdnUrl(
        source,
        defaultCDNService: defaultCDNService,
        isAudio: isAudio,
      ),
    ];
    for (final url in source) {
      final transformed = getCdnUrl(
        [url],
        defaultCDNService: defaultCDNService,
        isAudio: isAudio,
      );
      if (!result.contains(transformed)) result.add(transformed);
      if (!result.contains(url)) result.add(url);
    }
    return result;
  }

  static String getLiveCdnUrl(CodecItem e, {int index = 0}) {
    final urlInfo = e.urlInfo.getOrFirst(index);
    return (liveCdnUrl ?? urlInfo.host) + e.baseUrl + urlInfo.extra;
  }

  static VideoDecodeFormatType selectCodec(
    Iterable<String> codecs,
    List<VideoDecodeFormatType> preferCodecs,
  ) {
    if (preferCodecs.isNotEmpty) {
      int bestIndex = preferCodecs.length;
      for (final e in codecs) {
        for (int i = 0; i < bestIndex; i++) {
          if (preferCodecs[i].codes.any(e.startsWith)) {
            bestIndex = i;
            if (bestIndex == 0) {
              return preferCodecs[0];
            }
            break;
          }
        }
      }
      if (bestIndex < preferCodecs.length) {
        return preferCodecs[bestIndex];
      }
    }
    for (final codec in codecs) {
      for (final value in VideoDecodeFormatType.values) {
        if (value.codes.any(codec.startsWith)) return value;
      }
    }
    return preferCodecs.firstOrNull ?? VideoDecodeFormatType.AVC;
  }

  /// 从实际轨道按设置页顺序选择，画质编号本身不表示质量高低。
  static int _findAvailableVideoQuality(
    List<VideoItem> videoList,
    List<int>? acceptQuality,
    int preferQuality,
  ) {
    final available = videoList.map((e) => e.quality.code).toSet();
    const qualities = VideoQuality.values;
    final preferredIndex = qualities.indexWhere((e) => e.code == preferQuality);
    if (preferredIndex >= 0) {
      for (var i = preferredIndex; i < qualities.length; i++) {
        if (available.contains(qualities[i].code)) return qualities[i].code;
      }
    } else if (available.contains(preferQuality)) {
      return preferQuality;
    }
    for (final quality in qualities) {
      if (available.contains(quality.code)) return quality.code;
    }
    return videoList.first.quality.code;
  }

  static (
    int targetQuality,
    FormatItem targetFormat,
    VideoDecodeFormatType targetDecode,
    VideoItem targetVideo,
  )
  findTargetVideo(
    List<VideoItem> videoList,
    int preferQuality,
    List<int>? acceptQuality,
    List<FormatItem>? supportFormats,
    List<VideoDecodeFormatType> preferCodecs,
  ) {
    if (videoList.isEmpty) throw StateError('没有可用视频轨道');

    final targetQuality = _findAvailableVideoQuality(
      videoList,
      acceptQuality,
      preferQuality,
    );

    final targetQaVideoList = videoList
        .where((e) => e.quality.code == targetQuality)
        .toList();
    final targetFormat =
        supportFormats?.firstWhereOrNull((e) => e.quality == targetQuality) ??
        FormatItem(
          quality: targetQuality,
          codecs: targetQaVideoList
              .map((e) => e.codecs)
              .whereType<String>()
              .toList(),
        );
    final codecs = targetFormat.codecs?.where((e) => e.isNotEmpty).toList();
    final targetDecode = VideoUtils.selectCodec(
      codecs != null && codecs.isNotEmpty
          ? codecs
          : targetQaVideoList.map((e) => e.codecs).whereType<String>(),
      preferCodecs,
    );

    final targetVideo = targetQaVideoList.firstWhere(
      (e) => e.codecs != null && targetDecode.codes.any(e.codecs!.startsWith),
      orElse: () => targetQaVideoList.first,
    );

    return (targetVideo.quality.code, targetFormat, targetDecode, targetVideo);
  }

  static AudioItem findTargetAudio(
    List<AudioItem> audioList,
    int preferQuality,
  ) {
    return AudioTrackSelector.select(
      tracks: audioList,
      preferredId: preferQuality,
      idOf: (track) => track.id,
    );
  }
}
