import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late final Future<AudioSession> _sessionReady;
  AudioSession? _session;
  bool _playInterrupted = false;
  bool _focusActive = false;

  AudioSession get session => _session!;

  Future<bool> setActive(bool active) async {
    final session = await _sessionReady;
    if (!Pref.enableAudioFocus) {
      if (_focusActive) {
        _focusActive = false;
        return session.setActive(false);
      }
      return false;
    }
    _focusActive = active;
    return session.setActive(active);
  }

  AudioSessionHandler() {
    _sessionReady = initSession();
  }

  Future<AudioSession> initSession() async {
    final session = await AudioSession.instance;
    _session = session;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      if (!Pref.enableAudioFocus) {
        _playInterrupted = false;
        return;
      }
      _onInterrupted(event);
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      videoPlayerServiceHandler?.onPause?.call() ??
          PlPlayerController.pauseIfExists();
    });

    return session;
  }

  Future<void> setFocusHandlingEnabled(bool enabled) async {
    if (enabled) {
      if (PlPlayerController.getPlayerStatusIfExists() ==
          PlayerStatus.playing) {
        await setActive(true);
      }
      return;
    }
    _playInterrupted = false;
    final session = await _sessionReady;
    if (_focusActive) {
      _focusActive = false;
      await session.setActive(false);
    }
  }

  void _onInterrupted(AudioInterruptionEvent event) {
    final player = PlPlayerController.instance;
    final servicePlaying = videoPlayerServiceHandler?.isPlaying?.call() ?? false;
    final playerPlaying = player?.playerStatus.isPlaying ?? false;

    if (event.begin) {
      switch (event.type) {
        case .duck:
          if (playerPlaying) {
            player!.setVolume(
              player.volume.value * 0.5,
              showIndicator: false,
            );
          }
        case .pause:
        case .unknown:
          if (servicePlaying) {
            _playInterrupted = true;
            videoPlayerServiceHandler?.onPause?.call();
          } else if (playerPlaying) {
            _playInterrupted = true;
            player!.pause(isInterrupt: true);
          }
      }
    } else {
      switch (event.type) {
        case .duck:
          if (playerPlaying) {
            player!.setVolume(
              player.volume.value * 2,
              showIndicator: false,
            );
          }
        case .pause:
          if (_playInterrupted) {
            _playInterrupted = false;
            videoPlayerServiceHandler?.onPlay?.call() ?? player?.play();
          }
        case .unknown:
      }
    }
  }
}
