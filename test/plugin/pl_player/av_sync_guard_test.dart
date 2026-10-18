import 'package:PiliPlus/plugin/pl_player/utils/av_sync_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('音画差不超过 0.3 秒时交给播放器追帧', () {
    expect(AvSyncGuard.needsSeek(0), isFalse);
    expect(AvSyncGuard.needsSeek(0.299), isFalse);
    expect(AvSyncGuard.needsSeek(0.3), isFalse);
  });

  test('音画差超过 0.3 秒时需要重定位', () {
    expect(AvSyncGuard.needsSeek(0.301), isTrue);
    expect(AvSyncGuard.needsSeek(4.5), isTrue);
  });

  test('不可用或反向偏差不触发重定位', () {
    expect(AvSyncGuard.needsSeek(null), isFalse);
    expect(AvSyncGuard.needsSeek(double.nan), isFalse);
    expect(AvSyncGuard.needsSeek(double.infinity), isFalse);
    expect(AvSyncGuard.needsSeek(-1), isFalse);
  });
}
