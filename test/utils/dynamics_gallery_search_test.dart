import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/utils/dynamics_up_navigation.dart';
import 'package:PiliPlus/utils/followed_up_search.dart';
import 'package:PiliPlus/utils/gallery_live_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = jsonDecode(
    File(
      'test/fixtures/dynamics_gallery_search/input.json',
    ).readAsStringSync(encoding: utf8),
  );
  final reference = jsonDecode(
    File(
      'test/fixtures/dynamics_gallery_search/reference.json',
    ).readAsStringSync(encoding: utf8),
  );

  test('固定样例：Live Photo 只显示当前页且首帧就绪的视频层', () {
    final gallery = input['gallery'] as List;
    final expected = reference['gallery'] as List;
    final expectedMount = reference['gallery_mount'] as List;
    final actual = gallery
        .map(
          (sample) => GalleryLivePhoto.shouldShowVideo(
            pageIndex: sample['page_index'] as int,
            currentIndex: sample['current_index'] as int,
            readyIndex: sample['ready_index'] as int,
          ),
        )
        .toList();
    final actualMount = gallery
        .map(
          (sample) => GalleryLivePhoto.shouldMountVideo(
            pageIndex: sample['page_index'] as int,
            currentIndex: sample['current_index'] as int,
          ),
        )
        .toList();

    expect(actual, expected);
    expect(actualMount, expectedMount);
  });

  test('固定样例：动态筛选栏固定入口与 UP 选择标签', () {
    final panel = input['panel'] as Map<String, dynamic>;
    final expected = reference['panel'] as Map<String, dynamic>;
    final fixedSlots = DynamicsUpNavigation.fixedPanelSlots
        .map((slot) => slot.name)
        .toList();

    expect(fixedSlots, expected['fixed_slots']);

    final selectionTabs = (panel['selections'] as List)
        .map(
          (selection) => DynamicsTabType
              .values[DynamicsUpNavigation.tabIndexFor(
                selection['mid'] as int,
              )]
              .name,
        )
        .toList();
    expect(selectionTabs, expected['selection_tabs']);
  });

  test('固定样例：已关注 UP 列表支持部分匹配、跨词与缩写模糊搜索', () {
    final sample = input['up_search'] as Map<String, dynamic>;
    final expected = reference['up_search'] as Map<String, dynamic>;
    final items = (sample['items'] as List)
        .map(
          (item) => (
            mid: item['mid'] as int,
            uname: item['uname'] as String,
          ),
        )
        .toList();
    final queries = (sample['cases'] as List)
        .map((item) => item['query'] as String)
        .toList();
    final actual = (sample['cases'] as List)
        .map(
          (item) => FollowedUpSearch.filter(
            items: items,
            query: item['query'] as String,
            nameOf: (item) => item.uname,
          ).map((item) => item.mid).toList(),
        )
        .toList();

    expect(queries, expected['queries']);
    expect(actual, expected['results']);
  });
}
