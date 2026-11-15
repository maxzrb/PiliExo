import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/utils/scroll_offset_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = jsonDecode(
    File('test/fixtures/upstream_220/input.json').readAsStringSync(),
  );
  final reference = jsonDecode(
    File('test/fixtures/upstream_220/reference.json').readAsStringSync(),
  );
  final groups = input['scroll'] as List;
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    test('固定样例：${group['name']}', () {
      final actual = (group['cases'] as List).map((c) {
        switch (c['op']) {
          case 'items':
            final items = (c['pages'] as List)
                .map<BaseEpisodeItem>(
                  (n) => n == 0
                      ? BaseEpisodeItem()
                      : EpisodeItem(
                          pages: List.generate(n as int, (_) => Part()),
                        ),
                )
                .toList();
            final r = calcItemOffset(index: c['index'], episodes: items);
            return [r.$1, r.$2, r.$3];
          case 'fixed':
            final r = calcFixedItemOffset(
              index: c['index'],
              itemCount: c['count'],
            );
            return [r.$1, r.$2];
          case 'height':
            return calcItemHeight(EpisodeItem());
          case 'adjust':
            return adjustScrollOffset(
              offset: (c['offset'] as num).toDouble(),
              remain: (c['remain'] as num).toDouble(),
              viewportDimension: (c['viewport'] as num).toDouble(),
              isReversed: c['reverse'],
            );
          case 'page':
            return calcPageItemOffset(
              index: c['index'],
              itemCount: c['count'],
              viewportDimension: (c['viewport'] as num).toDouble(),
            );
          case 'separated':
            return calcPageItemOffsetSeparated(
              index: c['index'],
              itemCount: c['count'],
              extent: (c['extent'] as num).toDouble(),
              separator: (c['separator'] as num).toDouble(),
              viewportDimension: (c['viewport'] as num).toDouble(),
            );
          default:
            throw StateError('未知样例操作');
        }
      }).toList();
      expect(actual, reference['scroll'][i]);
    });
  }
}
