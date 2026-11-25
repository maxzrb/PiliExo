import 'dart:async' show Timer;
import 'dart:ui' show TargetImageSize;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show SynchronousFuture, debugPrint, kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:octo_image/octo_image.dart';

class NetworkImgLayer extends StatefulWidget {
  const NetworkImgLayer({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    this.type = .def,
    this.fadeOutDuration = const Duration(milliseconds: 120),
    this.fadeInDuration = const Duration(milliseconds: 120),
    this.quality = 1,
    this.borderRadius = Style.mdRadius,
    this.getPlaceHolder,
    this.fit = .cover,
    this.alignment = .center,
    this.cacheWidth,
    this.maxRetries = 2,
  });

  final String? src;
  final double width;
  final double height;
  final ImageType type;
  final Duration fadeOutDuration;
  final Duration fadeInDuration;
  final int quality;
  final BorderRadius borderRadius;
  final ValueGetter<Widget>? getPlaceHolder;
  final BoxFit fit;
  final Alignment alignment;
  final bool? cacheWidth;

  /// 瞬时网络失败的最多重试次数；0 表示不重试。
  final int maxRetries;

  static Color? reduceLuxColor = Pref.reduceLuxColor;
  static bool reduce = false;

  /// 首次失败后快速重试，第二次失败后稍等再试，避免无限请求。
  static const retryDelays = <Duration>[
    Duration(milliseconds: 350),
    Duration(milliseconds: 1200),
  ];

  /// 返回第 [retry] 次失败后的等待时间；达到上限后返回 null。
  static Duration? retryDelayFor(int retry, {int maxRetries = 2}) {
    if (retry < 0 || retry >= maxRetries) return null;
    return retryDelays[retry.clamp(0, retryDelays.length - 1)];
  }

  @override
  State<NetworkImgLayer> createState() => _NetworkImgLayerState();
}

class _NetworkImgLayerState extends State<NetworkImgLayer> {
  int _retry = 0;
  Timer? _retryTimer;

  @override
  void didUpdateWidget(covariant NetworkImgLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _retryTimer?.cancel();
      _retry = 0;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmote = widget.type == ImageType.emote;
    final isAvatar = widget.type == ImageType.avatar;
    if (widget.src?.isNotEmpty == true) {
      Widget child = _buildImage(
        context,
        isEmote: isEmote,
        isAvatar: isAvatar,
      );
      if (isEmote) {
        return child;
      } else if (isAvatar) {
        return ClipOval(child: child);
      } else {
        return ClipRRect(borderRadius: widget.borderRadius, child: child);
      }
    } else {
      return widget.getPlaceHolder?.call() ??
          _placeholder(context, isEmote: isEmote, isAvatar: isAvatar);
    }
  }

  Widget _buildImage(
    BuildContext context, {
    required bool isEmote,
    required bool isAvatar,
  }) {
    final width = widget.width.isFinite
        ? widget.width.cacheSize(context)
        : null;
    final height = widget.height.isFinite
        ? widget.height.cacheSize(context)
        : null;
    final byWidth = widget.cacheWidth ?? widget.width <= widget.height;
    final imageUrl = ImageUtils.thumbnailUrl(widget.src, widget.quality);
    final provider = CachedNetworkImageProvider(imageUrl);
    final ImageProvider image =
        widget.fit == BoxFit.cover &&
            width != null &&
            width > 0 &&
            height != null &&
            height > 0
        ? _CoverImage((provider: provider, width: width, height: height))
        : ResizeImage.resizeIfNeeded(
            byWidth ? width : null,
            byWidth ? null : height,
            provider,
          );
    Widget placeholder() =>
        widget.getPlaceHolder?.call() ??
        _placeholder(context, isEmote: isEmote, isAvatar: isAvatar);
    return OctoImage(
      // 变更 key 可绕过失败的图像流，重新发起一次请求。
      key: ValueKey('$imageUrl#$_retry'),
      gaplessPlayback: true,
      image: image,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      fadeOutDuration: widget.fadeOutDuration,
      fadeInDuration: widget.fadeInDuration,
      filterQuality: FilterQuality.low,
      colorBlendMode: NetworkImgLayer.reduce ? BlendMode.modulate : null,
      color: NetworkImgLayer.reduce ? NetworkImgLayer.reduceLuxColor : null,
      imageBuilder: (_, child) {
        _retryTimer?.cancel();
        _retryTimer = null;
        _retry = 0;
        return child;
      },
      placeholderBuilder: (_) => placeholder(),
      errorBuilder: (_, error, _) {
        _scheduleRetry(imageUrl, error);
        return placeholder();
      },
    );
  }

  void _scheduleRetry(String url, Object error) {
    if (!mounted || _retryTimer != null) return;
    final delay = NetworkImgLayer.retryDelayFor(
      _retry,
      maxRetries: widget.maxRetries,
    );
    if (delay == null) return;
    _retry++;
    if (kDebugMode) {
      debugPrint('NetworkImgLayer retry $_retry: $url ($error)');
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (mounted) setState(() {});
    });
  }

  Widget _placeholder(
    BuildContext context, {
    required bool isEmote,
    required bool isAvatar,
  }) {
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: isEmote ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        shape: isAvatar ? BoxShape.circle : BoxShape.rectangle,
        color: ColorScheme.of(context).onInverseSurface.withValues(alpha: 0.4),
        borderRadius: isEmote || isAvatar ? null : widget.borderRadius,
      ),
      child: Center(
        child: Image.asset(
          isAvatar ? Assets.avatarPlaceHolder : Assets.loading,
          width: widget.width,
          height: widget.height,
          cacheWidth: widget.width.cacheSize(context),
          colorBlendMode: NetworkImgLayer.reduce ? BlendMode.modulate : null,
          color: NetworkImgLayer.reduce ? NetworkImgLayer.reduceLuxColor : null,
        ),
      ),
    );
  }
}

typedef _CoverImageKey = ({
  CachedNetworkImageProvider provider,
  int width,
  int height,
});

class _CoverImage extends ImageProvider<_CoverImageKey> {
  const _CoverImage(this._key);

  final _CoverImageKey _key;

  @override
  Future<_CoverImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(_key);

  @override
  ImageStreamCompleter loadImage(
    _CoverImageKey key,
    ImageDecoderCallback decode,
  ) {
    final image = key.provider.loadImage(
      key.provider,
      (buffer, {getTargetSize}) => decode(
        buffer,
        getTargetSize: (width, height) {
          // 按铺满卡片所需的边解码，保留原比例并让绘制阶段裁切。
          if (key.width * height >= key.height * width) {
            return TargetImageSize(
              width: key.width < width ? key.width : width,
            );
          }
          return TargetImageSize(
            height: key.height < height ? key.height : height,
          );
        },
      ),
    );
    return image..addEphemeralErrorListener((_, _) {
      // 缓存组件只知道原始 provider 的键，失败时也清掉当前尺寸的键。
      imageCache.evict(key);
    });
  }

  @override
  bool operator ==(Object other) => other is _CoverImage && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}
