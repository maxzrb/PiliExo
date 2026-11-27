import 'dart:math' as math;

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:characters/characters.dart';

abstract final class DanmakuDensityTrend {
  static const _segmentLengthMs = 6 * 60 * 1000;

  static Future<List<double>?> load({
    required int cid,
    required int durationMs,
    required bool Function() isCurrent,
  }) async {
    if (cid <= 0 || durationMs <= 0) return null;
    final segmentCount = (durationMs / _segmentLengthMs).ceil();
    final elements = <DanmakuElem>[];
    var nextSegment = 1;
    Future<void> fetch() async {
      while (isCurrent() && nextSegment <= segmentCount) {
        final result = await DmGrpc.dmSegMobile(
          cid: cid,
          segmentIndex: nextSegment++,
        );
        if (result case Success(:final response)) {
          elements.addAll(response.elems);
        }
      }
    }

    await Future.wait([fetch(), if (segmentCount > 1) fetch()]);
    return isCurrent() ? build(elements, durationMs) : null;
  }

  static List<double>? build(Iterable<DanmakuElem> elements, int durationMs) {
    if (durationMs <= 0) return null;
    final valid = elements
        .where(
          (element) =>
              element.progress >= 0 &&
              element.progress <= durationMs &&
              element.content.isNotEmpty &&
              element.mode != 8 &&
              element.mode != 9,
        )
        .toList();
    if (valid.isEmpty) return null;

    final intervals = (durationMs / 1000).ceil().clamp(1, 400);
    final stepMs = durationMs / intervals;
    final densityPerMinute = valid.length * 60000 / durationMs;
    final windowMs = (8000 / math.sqrt(math.max(1, densityPerMinute / 10)))
        .clamp(
          2000,
          8000,
        );
    final sigma = math.max(stepMs * 0.5, windowMs / 3);
    final chart = List<double>.filled(intervals + 1, 0);

    for (final element in valid) {
      final time = element.progress;
      final first = ((time - 3 * sigma) / stepMs).ceil().clamp(0, intervals);
      final last = ((time + 3 * sigma) / stepMs).floor().clamp(0, intervals);
      final fontScale = element.fontsize <= 0
          ? 1.0
          : (element.fontsize / 25).clamp(0.7, 2.5);
      final weight =
          math.sqrt(element.content.characters.length) *
          math.pow(fontScale, 1.5);
      for (var index = first; index <= last; index++) {
        final distance = (index * stepMs - time) / sigma;
        chart[index] += weight * math.exp(-0.5 * distance * distance);
      }
    }
    return chart.map((density) => math.pow(density, 0.8).toDouble()).toList();
  }
}
