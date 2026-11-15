/*
 * This file is part of PiliPlus
 *
 * PiliPlus is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * PiliPlus is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PiliPlus.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:PiliPlus/common/widgets/colored_box_transition.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/gesture/image_double_tap_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/gesture/image_horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/gesture/image_tap_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/image_viewer/image.dart';
import 'package:PiliPlus/common/widgets/image_viewer/loading_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarScrollPhysics;
import 'package:PiliPlus/main.dart' show tmpPadding;
import 'package:PiliPlus/models/common/image_preview_type.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/gallery_live_photo.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/max_screen_size.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/gestures.dart' show LongPressGestureRecognizer;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide Image;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

///
/// created by dom on 2026/02/14
///

class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    this.minScale = 1.0,
    this.maxScale = 8.0,
    required this.quality,
    required this.sources,
    this.initIndex = 0,
    this.onPageChanged,
    this.tag = '',
  });

  final double minScale;
  final double maxScale;
  final int quality;
  final List<SourceModel> sources;
  final int initIndex;
  final ValueChanged<int>? onPageChanged;
  final String tag;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer>
    with TickerProviderStateMixin {
  late Size _containerSize;
  late final int _quality;
  late final RxInt _currIndex;
  EdgeInsets? _padding;

  Player? _player;
  final Rx<VideoController?> _videoController = Rx(null);
  Future<void>? _playerInitFuture;
  Future<void> _livePhotoQueue = Future<void>.value();
  int _livePhotoGeneration = 0;
  late final RxInt _livePhotoReadyIndex;
  int? _prewarmedLiveIndex;
  String? _prewarmedLiveUrl;

  late final PageController _pageController;

  late final ImageTapGestureRecognizer _tapGestureRecognizer;
  late final ImageDoubleTapGestureRecognizer _doubleTapGestureRecognizer;
  late final ImageHorizontalDragGestureRecognizer
  _horizontalDragGestureRecognizer;
  ImageHorizontalDragGestureRecognizer horizontalDragGestureRecognizer() {
    return _horizontalDragGestureRecognizer;
  }

  late final LongPressGestureRecognizer _longPressGestureRecognizer;

  late final AnimationController _animateController;
  late final AnimationController _livePhotoCoverController;
  late final Animation<Color?> _opacityAnimation;
  double dx = 0, dy = 0;

  Offset _offset = Offset.zero;
  bool _dragging = false;

  String _getActualUrl(String url) {
    return _quality != 100
        ? ImageUtils.thumbnailUrl(url, _quality)
        : url.http2https;
  }

  Future<void> _initPlayer() async {
    assert(_player == null);
    final player = await Player.create();
    final videoController = await VideoController.create(player);
    if (!mounted) {
      player.dispose();
      return;
    }
    _player = player;
    _videoController.value = videoController;
  }

  Future<void> _ensurePlayer() {
    if (_player != null) return Future<void>.value();
    return _playerInitFuture ??= _initPlayer();
  }

  int? _adjacentLiveIndex(int index) {
    for (final candidate in [index + 1, index - 1]) {
      if (candidate >= 0 &&
          candidate < widget.sources.length &&
          widget.sources[candidate].sourceType == .livePhoto) {
        return candidate;
      }
    }
    return null;
  }

  Future<bool> _waitForPlayback(Player player) async {
    const threshold = Duration(milliseconds: 200);
    if (player.state.position >= threshold) return true;
    try {
      await player.stream.position
          .firstWhere((position) => position >= threshold)
          .timeout(const Duration(seconds: 3));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _queueLivePhotoActivation(int index) {
    final generation = ++_livePhotoGeneration;
    _livePhotoQueue = _livePhotoQueue.then((_) async {
      try {
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != index) {
          return;
        }
        final item = widget.sources[index];
        if (item.sourceType != .livePhoto) return;
        final isPrewarmed =
            _prewarmedLiveIndex == index && _prewarmedLiveUrl == item.liveUrl;
        _prewarmedLiveIndex = null;
        _prewarmedLiveUrl = null;

        await _ensurePlayer();
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != index ||
            _player == null) {
          return;
        }

        if (!isPrewarmed) {
          // 先在暂停状态完成首帧解码，避免播放中的纹理分块直接闪现。
          await _player!.open(Media(item.liveUrl!), play: false);
          if (!mounted ||
              generation != _livePhotoGeneration ||
              _currIndex.value != index) {
            // 切页后旧任务才完成时，避免旧 Live Photo 继续播放声音。
            await _player?.pause();
            return;
          }

          // 等纹理完成首帧提交；视频层此时仅以极低透明度挂载。
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              generation != _livePhotoGeneration ||
              _currIndex.value != index) {
            return;
          }
        }

        // 隐藏的视频层先推进到稳定帧率，再淡入可见。
        await _player!.play();
        final hasPlayback = await _waitForPlayback(_player!);
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != index ||
            !hasPlayback) {
          await _player?.pause();
          return;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != index) {
          await _player?.pause();
          return;
        }
        _livePhotoReadyIndex.value = index;
        await _livePhotoCoverController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } catch (e, s) {
        debugPrint('Live Photo 播放失败: $e\n$s');
      }
    });
  }

  void _queueAdjacentLivePhotoPrewarm(int currentIndex) {
    final targetIndex = _adjacentLiveIndex(currentIndex);
    if (targetIndex == null) {
      _prewarmedLiveIndex = null;
      _prewarmedLiveUrl = null;
      _scheduleLivePhotoRelease();
      return;
    }

    final generation = ++_livePhotoGeneration;
    _livePhotoQueue = _livePhotoQueue.then((_) async {
      try {
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != currentIndex ||
            widget.sources[currentIndex].sourceType == .livePhoto) {
          return;
        }
        final item = widget.sources[targetIndex];
        if (_prewarmedLiveIndex == targetIndex &&
            _prewarmedLiveUrl == item.liveUrl) {
          return;
        }

        await _ensurePlayer();
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != currentIndex ||
            _player == null) {
          return;
        }

        _prewarmedLiveIndex = null;
        _prewarmedLiveUrl = null;
        await _player!.open(Media(item.liveUrl!), play: false);
        if (!mounted ||
            generation != _livePhotoGeneration ||
            _currIndex.value != currentIndex) {
          return;
        }
        _prewarmedLiveIndex = targetIndex;
        _prewarmedLiveUrl = item.liveUrl;
        await WidgetsBinding.instance.endOfFrame;
      } catch (e, s) {
        debugPrint('Live Photo 预加载失败: $e\n$s');
      }
    });
  }

  void _deactivateLivePhoto() {
    _livePhotoGeneration++;
    _livePhotoCoverController.value = 1;
    _livePhotoReadyIndex.value = GalleryLivePhoto.none;
    _player?.pause();
  }

  void _scheduleLivePhotoRelease() {
    final generation = _livePhotoGeneration;
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted || generation != _livePhotoGeneration) return;
      if (_prewarmedLiveIndex != null) return;
      final index = _currIndex.value;
      if (index >= 0 &&
          index < widget.sources.length &&
          widget.sources[index].sourceType == .livePhoto) {
        return;
      }
      try {
        await _player?.stop();
      } catch (e, s) {
        debugPrint('Live Photo 资源清理失败: $e\n$s');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _quality = Pref.previewQ;
    _currIndex = widget.initIndex.obs;
    _livePhotoReadyIndex = GalleryLivePhoto.none.obs;
    _livePhotoCoverController = AnimationController(
      duration: const Duration(milliseconds: 180),
      value: 1,
      vsync: this,
    );
    final item = widget.sources[widget.initIndex];
    if (item.sourceType == .livePhoto) {
      unawaited(_ensurePlayer());
      _queueLivePhotoActivation(widget.initIndex);
    } else {
      _queueAdjacentLivePhotoPrewarm(widget.initIndex);
    }

    _pageController = PageController(initialPage: widget.initIndex);

    final gestureSettings = MediaQuery.maybeGestureSettingsOf(Get.context!);
    _tapGestureRecognizer = ImageTapGestureRecognizer()
      // ..onTap = _onTap
      ..gestureSettings = gestureSettings;
    if (PlatformUtils.isDesktop) {
      _tapGestureRecognizer.onSecondaryTapUp = _showDesktopMenu;
    }
    _doubleTapGestureRecognizer = ImageDoubleTapGestureRecognizer()
      ..onDoubleTap = () {}
      ..gestureSettings = gestureSettings;
    _horizontalDragGestureRecognizer = ImageHorizontalDragGestureRecognizer();
    _longPressGestureRecognizer = LongPressGestureRecognizer()
      ..onLongPress = _onLongPress
      ..gestureSettings = gestureSettings;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _tapGestureRecognizer.onTap = _onTap;
      }
    });

    _animateController = AnimationController(
      duration: const Duration(
        milliseconds: 750,
      ), // reverse only if value <= 0.2
      vsync: this,
    );

    _opacityAnimation = _animateController.drive(
      ColorTween(
        begin: Colors.black,
        end: Colors.transparent,
      ),
    );
  }

  late final bool _hideSystemBar;

  void _initHideSystemBar() {
    if (Platform.isAndroid) {
      if (showSystemBar_) {
        final size = DeviceUtils.size;
        _hideSystemBar = !MaxScreenSize.isWindowMode(
          width: size.width,
          height: size.height,
        );
      } else {
        _hideSystemBar = false;
      }
    } else if (Platform.isIOS) {
      _hideSystemBar = showSystemBar_;
    } else {
      _hideSystemBar = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_padding == null) {
      final padding = MediaQuery.viewPaddingOf(context);
      _padding = padding;
      _initHideSystemBar();
      if (_hideSystemBar) {
        tmpPadding = padding;
        hideSystemBar()!.whenComplete(
          () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => tmpPadding = null,
          ),
        );
      }
    }
  }

  Matrix4 _onTransform(double val) {
    final scale = val.lerp(1.0, 0.25);

    // Matrix4.identity()
    //   ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
    //   ..translateByDouble(size.width * val * dx, size.height * val * dy, 0, 1)
    //   ..scaleByDouble(scale, scale, scale, 1)
    //   ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);

    final tmp = (1.0 - scale) / 2.0;
    return Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(
      _containerSize.width * (val * dx + tmp),
      _containerSize.height * (val * dy + tmp),
      0,
    );
  }

  void _updateMoveAnimation() {
    dy = _offset.dy.sign;
    if (dy == 0) {
      dx = 0;
    } else {
      dx = _offset.dx / _offset.dy.abs();
    }
  }

  void _onDragStart(ScaleStartDetails details) {
    _dragging = true;

    if (_animateController.isAnimating) {
      _animateController.stop();
    } else {
      _offset = Offset.zero;
      _animateController.value = 0.0;
    }
    _updateMoveAnimation();
  }

  void _onDragUpdate(ScaleUpdateDetails details) {
    if (!_dragging || _animateController.isAnimating) {
      return;
    }

    _offset += details.focalPointDelta;
    _updateMoveAnimation();

    if (!_animateController.isAnimating) {
      _animateController.value = _offset.dy.abs() / _containerSize.height;
    }
  }

  void _onDragEnd(ScaleEndDetails details) {
    if (!_dragging || _animateController.isAnimating) {
      return;
    }

    _dragging = false;

    if (!_animateController.isDismissed) {
      if (_animateController.value > 0.2) {
        Get.back();
      } else {
        _animateController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _livePhotoGeneration++;
    _player?.dispose();
    _player = null;
    _videoController.value = null;
    _pageController.dispose();
    _animateController.dispose();
    _livePhotoCoverController.dispose();
    _tapGestureRecognizer.dispose();
    _doubleTapGestureRecognizer
      ..onDoubleTapDown = null
      ..onDoubleTap = null
      ..dispose();
    _longPressGestureRecognizer.dispose();
    if (widget.quality != _quality) {
      for (final item in widget.sources) {
        if (item.sourceType == SourceType.networkImage) {
          CachedNetworkImageProvider(_getActualUrl(item.url)).evict();
        }
      }
    }
    Future.delayed(const Duration(milliseconds: 200), _currIndex.close);
    super.dispose();
    if (_hideSystemBar) {
      showSystemBar();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _tapGestureRecognizer.addPointer(event);
    _doubleTapGestureRecognizer.addPointer(event);
    _longPressGestureRecognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: .opaque,
      onPointerDown: _onPointerDown,
      child: Stack(
        fit: .expand,
        alignment: .center,
        clipBehavior: .none,
        children: [
          ColoredBoxTransition(color: _opacityAnimation),
          LayoutBuilder(
            builder: (context, constraints) {
              _containerSize = constraints.biggest;
              return MatrixTransition(
                alignment: .topLeft,
                animation: _animateController,
                onTransform: _onTransform,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: tabBarScrollPhysics,
                  ),
                  itemCount: widget.sources.length,
                  itemBuilder: _itemBuilder,
                  allowImplicitScrolling: true,
                  horizontalDragGestureRecognizer:
                      horizontalDragGestureRecognizer,
                ),
              );
            },
          ),
          _buildLivePhotoLoading,
          _buildIndicator,
        ],
      ),
    );
  }

  Widget get _buildLivePhotoLoading => Obx(() {
    final index = _currIndex.value;
    if (index < 0 ||
        index >= widget.sources.length ||
        widget.sources[index].sourceType != .livePhoto ||
        GalleryLivePhoto.shouldShowVideo(
          pageIndex: index,
          currentIndex: index,
          readyIndex: _livePhotoReadyIndex.value,
        )) {
      return const SizedBox.shrink();
    }
    return const IgnorePointer(
      child: Center(
        child: M3ELoadingIndicator(size: Size.square(36)),
      ),
    );
  });

  Widget get _buildIndicator => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: Container(
        padding: _padding! + const EdgeInsets.fromLTRB(12, 8, 20, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.3),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Obx(
          () => Text(
            "${_currIndex.value + 1}/${widget.sources.length}",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  void _onPageChanged(int index) {
    _deactivateLivePhoto();
    _currIndex.value = index;
    if (widget.sources[index].sourceType == .livePhoto) {
      unawaited(_ensurePlayer());
      _queueLivePhotoActivation(index);
    } else {
      _queueAdjacentLivePhotoPrewarm(index);
    }
    widget.onPageChanged?.call(index);
  }

  late final ValueChanged<int>? _onChangePage = widget.sources.length == 1
      ? null
      : (int offset) {
          final currPage = _pageController.page?.round() ?? 0;
          final nextPage = (currPage + offset).clamp(
            0,
            widget.sources.length - 1,
          );
          if (nextPage != currPage) {
            _pageController.animateToPage(
              nextPage,
              duration: const Duration(milliseconds: 200),
              curve: Curves.ease,
            );
          }
        };

  Widget _itemBuilder(BuildContext context, int index) {
    final item = widget.sources[index];
    final Widget child;
    switch (item.sourceType) {
      case SourceType.fileImage:
        child = Image.file(
          key: ValueKey('gallery_image_$index'),
          File(item.url),
          filterQuality: .low,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          containerSize: _containerSize,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
          horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
          onChangePage: _onChangePage,
        );
      case SourceType.networkImage:
        final isLongPic = item.isLongPic;
        child = Image(
          key: ValueKey('gallery_image_$index'),
          image: CachedNetworkImageProvider(_getActualUrl(item.url)),
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          containerSize: _containerSize,
          gaplessPlayback: true,
          doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
          horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
          onChangePage: _onChangePage,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            if (frame == null) {
              if (widget.quality == _quality) {
                return child;
              } else {
                return Image(
                  image: ResizeImage.resizeIfNeeded(
                    _containerSize.width.cacheSize(context),
                    null,
                    CachedNetworkImageProvider(
                      ImageUtils.thumbnailUrl(item.url, widget.quality),
                    ),
                  ),
                  minScale: widget.minScale,
                  maxScale: widget.maxScale,
                  containerSize: _containerSize,
                  onDragStart: null,
                  onDragUpdate: null,
                  onDragEnd: null,
                  doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
                  horizontalDragGestureRecognizer:
                      _horizontalDragGestureRecognizer,
                  onChangePage: _onChangePage,
                );
                // final isLongPic = item.isLongPic;
                // return CachedNetworkImage(
                //   fadeInDuration: Duration.zero,
                //   fadeOutDuration: Duration.zero,
                //   // fit: isLongPic ? .fitWidth : null,
                //   // alignment: isLongPic ? .topCenter : .center,
                //   imageUrl: ImageUtils.thumbnailUrl(item.url, widget.quality),
                //   placeholder: (_, _) => const SizedBox.expand(),
                // );
              }
            }
            return child;
          },
          loadingBuilder: loadingBuilder,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
        );
        if (isLongPic) {
          return child;
        }
      case SourceType.livePhoto:
        child = Obx(() {
          final videoController = _videoController.value;
          final isCurrent = _currIndex.value == index;
          final shouldMount = GalleryLivePhoto.shouldMountVideo(
            pageIndex: index,
            currentIndex: _currIndex.value,
          );
          return Image(
            key: ValueKey('gallery_image_$index'),
            image: CachedNetworkImageProvider(_getActualUrl(item.url)),
            minScale: widget.minScale,
            maxScale: widget.maxScale,
            containerSize: _containerSize,
            gaplessPlayback: true,
            opacity: isCurrent
                ? _livePhotoCoverController
                : const AlwaysStoppedAnimation(1.0),
            doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
            horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
            onChangePage: _onChangePage,
            loadingBuilder: loadingBuilder,
            onDragStart: _onDragStart,
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
            overlayBuilder: videoController == null || !shouldMount
                ? null
                : (context, _) =>
                      _LivePhotoOverlay(controller: videoController),
          );
        });
    }
    return Hero(tag: '${item.url}${widget.tag}', child: child);
  }

  static const Duration _kTapDiff = Duration(milliseconds: 300);

  void _onTap() {
    if (_tapGestureRecognizer.timeStamp -
            _doubleTapGestureRecognizer.timeStamp <
        _kTapDiff) {
      return;
    }
    Get.back();
  }

  void _onLongPress() {
    final item = widget.sources[_currIndex.value];
    if (item.sourceType == .fileImage) return;
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (PlatformUtils.isMobile)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.onShareImg(item.url);
              },
              child: const Text('分享', style: TextStyle(fontSize: 14)),
            ),
          DialogOption(
            onPressed: () {
              Get.back();
              Utils.copyText(item.url);
            },
            child: const Text('复制链接', style: TextStyle(fontSize: 14)),
          ),
          DialogOption(
            onPressed: () {
              Get.back();
              ImageUtils.downloadImg([item.url]);
            },
            child: const Text('保存图片', style: TextStyle(fontSize: 14)),
          ),
          if (PlatformUtils.isDesktop)
            DialogOption(
              onPressed: () {
                Get.back();
                PageUtils.launchURL(item.url);
              },
              child: const Text('网页打开', style: TextStyle(fontSize: 14)),
            )
          else if (widget.sources.length > 1)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.downloadImg(
                  widget.sources.map((item) => item.url).toList(),
                );
              },
              child: const Text('保存全部图片', style: TextStyle(fontSize: 14)),
            ),
          if (item.sourceType == SourceType.livePhoto)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.downloadLivePhoto(
                  url: item.url,
                  liveUrl: item.liveUrl!,
                  width: item.width!,
                  height: item.height!,
                );
              },
              child: Text(
                '保存${Platform.isIOS ? ' Live Photo' : '视频'}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  void _showDesktopMenu(TapUpDetails details) {
    final item = widget.sources[_currIndex.value];
    if (item.sourceType == .fileImage) return;
    showMenu(
      context: context,
      position: PageUtils.menuPosition(details.globalPosition),
      items: [
        PopupMenuItem(
          height: 42,
          onTap: () => ImageUtils.downloadImg([item.url]),
          child: const Text('保存图片', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem(
          height: 42,
          onTap: () => Utils.copyText(item.url),
          child: const Text('复制链接', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem(
          height: 42,
          onTap: () => PageUtils.launchURL(item.url),
          child: const Text('网页打开', style: TextStyle(fontSize: 14)),
        ),
        if (item.sourceType == SourceType.livePhoto)
          PopupMenuItem(
            height: 42,
            onTap: () => ImageUtils.downloadLivePhoto(
              url: item.url,
              liveUrl: item.liveUrl!,
              width: item.width!,
              height: item.height!,
            ),
            child: const Text('保存视频', style: TextStyle(fontSize: 14)),
          ),
      ],
    );
  }

  Widget loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  ) {
    return Stack(
      fit: .expand,
      alignment: .center,
      clipBehavior: .none,
      children: [
        child,
        if (loadingProgress != null &&
            loadingProgress.expectedTotalBytes != null &&
            loadingProgress.cumulativeBytesLoaded !=
                loadingProgress.expectedTotalBytes)
          Center(
            child: LoadingIndicator(
              size: 39.4,
              progress:
                  loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!,
            ),
          ),
      ],
    );
  }
}

class _LivePhotoOverlay extends StatelessWidget {
  const _LivePhotoOverlay({required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SimpleVideo(
            controller: controller,
            fill: Colors.transparent,
          ),
        ),
      ),
    );
  }
}
