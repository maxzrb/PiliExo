import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/backends/media3_hdr.dart';
import 'package:PiliPlus/plugin/pl_player/backends/mpv_hdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class HdrStartupCover extends StatefulWidget {
  const HdrStartupCover({
    super.key,
    required this.child,
    required this.cover,
    this.media3,
    this.mpv,
  });

  final Widget child;
  final Widget cover;
  final HdrMedia3Controller? media3;
  final MpvHdrController? mpv;

  @override
  State<HdrStartupCover> createState() => _HdrStartupCoverState();
}

class _HdrStartupCoverState extends State<HdrStartupCover> {
  Animation<double>? _entrance;
  StreamSubscription<HdrMedia3Event>? _media3Events;
  Timer? _mpvRetry;
  bool _mountSurface = false;
  bool _showCover = true;
  int _mpvAttempts = 0;

  @override
  void initState() {
    super.initState();
    _media3Events = widget.media3?.events.listen((event) {
      if (event.type == 'error' ||
          (_mountSurface && event.type == 'firstFrame')) {
        _reveal();
      }
    });
    widget.mpv?.diagnostics.addListener(_onMpvOutputChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mountSurface) return;
    final route = ModalRoute.of(context);
    final entrance = route?.animation;
    if (entrance != _entrance) {
      _entrance?.removeStatusListener(_onEntranceStatus);
      _entrance = entrance;
      entrance?.addStatusListener(_onEntranceStatus);
    }
    if (route?.offstage != true && (entrance == null || entrance.isCompleted)) {
      _mountSurface = true;
      _entrance?.removeStatusListener(_onEntranceStatus);
      _onMpvOutputChanged();
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _entrance?.removeStatusListener(_onEntranceStatus);
    setState(() => _mountSurface = true);
    _onMpvOutputChanged();
  }

  void _onMpvOutputChanged() {
    final mpv = widget.mpv;
    if (!_mountSurface ||
        !_showCover ||
        _mpvRetry != null ||
        mpv?.diagnostics.value['configured'] != true) {
      return;
    }
    _mpvRetry = Timer(const Duration(milliseconds: 100), () async {
      var hasFrame = false;
      try {
        hasFrame =
            await mpv!.captureAmbientPixels(width: 16, height: 16) != null;
      } on PlatformException {
        if (!mounted) return;
      }
      if (!mounted) return;
      _mpvRetry = null;
      if (hasFrame || ++_mpvAttempts >= 8) {
        _reveal();
      } else {
        _onMpvOutputChanged();
      }
    });
  }

  void _reveal() {
    if (_showCover) setState(() => _showCover = false);
  }

  @override
  void dispose() {
    _entrance?.removeStatusListener(_onEntranceStatus);
    _media3Events?.cancel();
    widget.mpv?.diagnostics.removeListener(_onMpvOutputChanged);
    _mpvRetry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_mountSurface) widget.child,
      if (_showCover) IgnorePointer(child: widget.cover),
    ],
  );
}
