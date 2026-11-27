import 'dart:io';

import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Owner extends BaseOwner {
  _Owner(int id, String nickname) {
    mid = id;
    name = nickname;
  }
}

class _Stat extends BaseStat {}

class _Video extends BaseVideoItemModel {
  _Video(int mid, String name, {bool followed = false}) {
    title = '视频标题';
    owner = _Owner(mid, name);
    stat = _Stat();
    isFollowed = followed;
  }
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory('tmp').createTemp('recommend-filter-');
    Hive.init(directory.absolute.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() {
    RecommendFilter.blockedMids = {1};
    RecommendFilter.allowedMids = {1, 2};
    RecommendFilter.exemptFilterForFollowed = true;
    RecommendFilter.upNameRegExp = RegExp('切片', caseSensitive: false);
  });

  test('明确屏蔽优先于白名单和已关注豁免', () {
    expect(
      RecommendFilter.filterWithExempt(_Video(1, '作者', followed: true)),
      isTrue,
    );
    expect(RecommendFilter.filterAll(_Video(1, '作者')), isTrue);
  });

  test('白名单和关注豁免可以跳过常规条件', () {
    expect(
      RecommendFilter.filterAll(_Video(2, '切片作者'), zoneMatches: true),
      isFalse,
    );
    expect(
      RecommendFilter.filterWithExempt(_Video(3, '切片作者', followed: true)),
      isFalse,
    );
  });

  test('昵称匹配过滤普通推荐项', () {
    expect(RecommendFilter.filterWithExempt(_Video(4, '切片作者')), isTrue);
    expect(RecommendFilter.filterWithExempt(_Video(5, '作者')), isFalse);
  });
}
