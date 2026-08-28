import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:material_ui/material_ui.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
  with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final StreamSubscription<PlayerStatus> subscription;
  late bool isPlaying;

  @override
  void initState() {
    super.initState();
    isPlaying = widget.plPlayerController.playerStatus.isPlaying;
    controller = AnimationController(
      vsync: this,
      value: isPlaying ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    subscription = widget.plPlayerController.playerStatus.listen((status) {
      final playing = status.isPlaying;
      if (mounted) {
        setState(() => isPlaying = playing);
      } else {
        isPlaying = playing;
      }
      if (playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.plPlayerController.onDoubleTapCenter,
        child: Center(
          child: AnimatedIcon(
            semanticLabel: isPlaying ? '暂停' : '播放',
            progress: controller,
            icon: AnimatedIcons.play_pause,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
