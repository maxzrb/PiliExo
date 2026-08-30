import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
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
      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      // final player = PlPlayerController.getInstance();
      if (event.begin) {
        if (playerStatus != PlayerStatus.playing) return;
        // if (!player.playerStatus.playing) return;
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 0.5,
              showIndicator: false,
            );
            // player.setVolume(player.volume.value * 0.5);
            break;
          case AudioInterruptionType.pause:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            break;
          case AudioInterruptionType.unknown:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 2,
              showIndicator: false,
            );
            // player.setVolume(player.volume.value * 2);
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) PlPlayerController.playIfExists();
            //player.play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
        _playInterrupted = false;
      }
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      PlPlayerController.pauseIfExists();
      // final player = PlPlayerController.getInstance();
      // if (player.playerStatus.playing) {
      //   player.pause();
      // }
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
}
