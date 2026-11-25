import 'package:PiliPlus/plugin/pl_player/utils/playback_seek_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('片尾冻结后拖回时间轴会恢复播放意图', () {
    expect(
      PlaybackSeekPolicy.shouldResumeAfterCompletedSeek(
        isLive: false,
        wasCompleted: true,
        playWhenReady: false,
        target: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      ),
      isTrue,
    );
  });

  test('普通暂停、直播、已请求播放或目标仍在片尾时不自动播放', () {
    expect(
      PlaybackSeekPolicy.shouldResumeAfterCompletedSeek(
        isLive: false,
        wasCompleted: false,
        playWhenReady: false,
        target: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      ),
      isFalse,
    );
    expect(
      PlaybackSeekPolicy.shouldResumeAfterCompletedSeek(
        isLive: true,
        wasCompleted: true,
        playWhenReady: false,
        target: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      ),
      isFalse,
    );
    expect(
      PlaybackSeekPolicy.shouldResumeAfterCompletedSeek(
        isLive: false,
        wasCompleted: true,
        playWhenReady: true,
        target: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      ),
      isFalse,
    );
    expect(
      PlaybackSeekPolicy.shouldResumeAfterCompletedSeek(
        isLive: false,
        wasCompleted: true,
        playWhenReady: false,
        target: const Duration(milliseconds: 59_900),
        duration: const Duration(seconds: 60),
      ),
      isFalse,
    );
  });

  test('只有观察到播放位置越过 seek 目标才结束片尾拖回事务', () {
    const target = Duration(seconds: 30);
    const duration = Duration(seconds: 60);

    expect(
      PlaybackSeekPolicy.hasAdvancedFromCompletedSeek(
        observed: const Duration(seconds: 30),
        target: target,
        duration: duration,
      ),
      isFalse,
    );
    expect(
      PlaybackSeekPolicy.hasAdvancedFromCompletedSeek(
        observed: const Duration(seconds: 31),
        target: target,
        duration: duration,
      ),
      isTrue,
    );
    expect(
      PlaybackSeekPolicy.hasAdvancedFromCompletedSeek(
        observed: duration,
        target: target,
        duration: duration,
      ),
      isFalse,
    );
  });
}
