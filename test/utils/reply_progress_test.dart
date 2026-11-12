import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/utils/reply_progress.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = jsonDecode(
    File('test/fixtures/reply_progress/input.json').readAsStringSync(
      encoding: utf8,
    ),
  );
  final reference = jsonDecode(
    File('test/fixtures/reply_progress/reference.json').readAsStringSync(
      encoding: utf8,
    ),
  );

  test('固定样例：楼中楼加载进度', () {
    final actual = (input['progress'] as List).map((item) {
      final sample = item as Map<String, dynamic>;
      return replyLoadProgress(
        loaded: sample['loaded'] as int,
        total: sample['total'] as int,
        isEnd: sample['is_end'] as bool,
      );
    }).toList();

    expect(actual, reference['progress']);
  });

  test('固定样例：分页总数合并', () {
    final actual = (input['total'] as List).map((item) {
      final sample = item as Map<String, dynamic>;
      return mergeReplyTotal(
        previous: sample['previous'] as int,
        incoming: sample['incoming'] as int,
        isRefresh: sample['is_refresh'] as bool,
      );
    }).toList();

    expect(actual, reference['total']);
  });

  test('固定样例：重复回复 id 只计一次', () {
    final sample = (input['unique'] as List).single as Map<String, dynamic>;
    final replies = (sample['ids'] as List)
        .map((id) => ReplyInfo(id: Int64(id as int)))
        .toList();

    expect(uniqueReplyCount(replies), (reference['unique'] as List).single);
  });

  test('固定样例：楼中楼滚动进度', () {
    final actual = (input['scroll'] as List).map((item) {
      final sample = item as Map<String, dynamic>;
      return replyScrollProgress(
        pixels: (sample['pixels'] as num).toDouble(),
        estimatedTotalExtent: (sample['estimated_total_extent'] as num)
            .toDouble(),
      );
    }).toList();

    expect(actual, reference['scroll']);
  });

  test('固定样例：楼中楼总高度估算', () {
    final actual = (input['extent'] as List).map((item) {
      final sample = item as Map<String, dynamic>;
      return estimateReplyTotalExtent(
        loadedExtent: (sample['loaded_extent'] as num).toDouble(),
        loadedPages: sample['loaded_pages'] as int,
        total: sample['total'] as int,
      );
    }).toList();

    expect(actual, reference['extent']);
  });
}
