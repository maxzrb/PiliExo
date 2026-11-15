import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('固定样例：图片瞬时失败重试窗口', () {
    final input = [
      (retry: 0, maxRetries: 2),
      (retry: 1, maxRetries: 2),
      (retry: 2, maxRetries: 2),
      (retry: -1, maxRetries: 2),
      (retry: 0, maxRetries: 0),
      (retry: 0, maxRetries: 1),
    ];
    final actual = input
        .map(
          (sample) => NetworkImgLayer.retryDelayFor(
            sample.retry,
            maxRetries: sample.maxRetries,
          )?.inMilliseconds,
        )
        .toList();
    expect(actual, [350, 1200, null, null, null, 350]);
  });
}
