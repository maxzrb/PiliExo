import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/pages/video/reply_reply/tree.dart';
import 'package:PiliPlus/utils/scroll_offset_helper.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final input = jsonDecode(
    File('test/fixtures/upstream_20261109/input.json').readAsStringSync(
      encoding: utf8,
    ),
  );
  final reference = jsonDecode(
    File('test/fixtures/upstream_20261109/reference.json').readAsStringSync(
      encoding: utf8,
    ),
  );

  test('固定样例：旧下载时间戳迁移并保留离线字幕/看点', () {
    final sample = input['download'] as Map<String, dynamic>;
    final entry = BiliDownloadEntryInfo.fromJson(
      Map<String, dynamic>.from(sample['json'] as Map),
      sample['entry_dir'] as String,
    );
    final expected = reference['download'] as Map<String, dynamic>;

    expect(entry.timeUpdateStamp, expected['time_update_stamp']);
    expect(entry.timeCreateStamp, expected['time_create_stamp']);
    expect(
      entry.subtitles!.map((e) => e.lan).toList(),
      expected['subtitle_languages'],
    );
    expect(
      entry.subtitles!
          .map((e) => (e as LocalSubtitle).path.replaceAll('\\', '/'))
          .toList(),
      expected['subtitle_paths'],
    );
    expect(
      entry.viewPoints!
          .map((e) => e.toSegment(entry.totalTimeMilli / 1000).end)
          .toList(),
      expected['view_point_ends'],
    );
  });

  test('固定样例：下载元数据写回毫秒时间戳', () {
    final sample = input['download'] as Map<String, dynamic>;
    final entry = BiliDownloadEntryInfo.fromJson(
      Map<String, dynamic>.from(sample['json'] as Map),
      sample['entry_dir'] as String,
    );
    final json = entry.toJson();
    final expected = reference['download'] as Map<String, dynamic>;
    expect(json['time_update_stamp'], expected['time_update_stamp']);
    expect(json['time_create_stamp'], expected['time_create_stamp']);
  });

  for (var i = 0; i < (input['trees'] as List).length; i++) {
    final sample = input['trees'][i] as Map<String, dynamic>;
    test('固定样例：${sample['name']}', () {
      final rootId = Int64(sample['root'] as int);
      final data = (sample['nodes'] as List)
          .map(
            (node) => ReplyInfo(
              id: Int64(node['id'] as int),
              parent: Int64(node['parent'] as int),
              dialog: Int64(node['dialog'] as int),
              root: rootId,
              ctime: Int64(node['ctime'] as int),
            ),
          )
          .toList();
      final tree = ReplyTree.build(
        data: data,
        seen: HashSet<Int64>.from(data.map((e) => e.id)),
        rootId: rootId,
        removed: {},
        foldDepth: sample['fold_depth'] as int,
      );
      final actual = tree
          .map(
            (node) => {
              'id': node.reply.id.toInt(),
              'depth': node.depth,
              'collapsed': node.collapsed,
            },
          )
          .toList();
      final expected = (reference['trees'] as List)[i];
      expect(actual, expected['visible']);
    });
  }

  test('固定样例：选集定位显式边距不重复叠加', () {
    final actual = (input['scroll'] as List)
        .map((sample) {
          final result = calcFixedItemOffset(
            index: sample['index'] as int,
            itemCount: sample['count'] as int,
            extent: (sample['extent'] as num).toDouble(),
            topPadding: (sample['top_padding'] as num).toDouble(),
            bottomPadding: (sample['bottom_padding'] as num).toDouble(),
          );
          return [result.$1, result.$2];
        })
        .toList();
    expect(actual, reference['scroll']);
  });
}
