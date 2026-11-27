import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/utils/danmaku_density_trend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('弹幕聚集处有连续峰值，越远权重越低', () {
    final chart = DanmakuDensityTrend.build(
      [DanmakuElem(progress: 30000, content: '到了')],
      60000,
    )!;

    expect(chart.length, 61);
    expect(chart[30], greaterThan(chart[29]));
    expect(chart[29], closeTo(chart[31], 1e-10));
    expect(chart[31], greaterThan(chart[34]));
    expect(chart.first, 0);
  });

  test('图表包含视频结束点并限制采样数', () {
    final chart = DanmakuDensityTrend.build(
      [DanmakuElem(progress: 3600500, content: '结束')],
      3600500,
    )!;

    expect(chart.length, 401);
    expect(chart.last, greaterThan(chart[399]));
  });

  test('无有效弹幕时不生成曲线', () {
    expect(
      DanmakuDensityTrend.build([
        DanmakuElem(progress: 200, mode: 8, content: '代码弹幕'),
        DanmakuElem(progress: 400, mode: 9, content: 'BAS'),
        DanmakuElem(progress: 800, content: ''),
        DanmakuElem(progress: 2000, content: '超出时长'),
      ], 1000),
      isNull,
    );
  });
}
