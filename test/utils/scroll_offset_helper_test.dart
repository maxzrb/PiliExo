import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/utils/scroll_offset_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('空列表和未知索引不会越界', () {
    expect(calcItemOffset(index: -1, episodes: []), (0.0, 0.0, 0.0));
    expect(calcFixedItemOffset(index: -1, itemCount: 0), (0.0, 0.0));
    expect(
      calcPageItemOffset(index: 4, itemCount: 0, viewportDimension: 500),
      0,
    );
    expect(calcItemOffset(index: 99, episodes: [BaseEpisodeItem()]).$2, 7);
  });
  test('合集多分P条目的前后高度均计入偏移', () {
    final items = [
      BaseEpisodeItem(),
      EpisodeItem(pages: [Part(), Part()]),
    ];
    expect(calcItemOffset(index: 0, episodes: items), (112.0, 7.0, 267.0));
    expect(calcItemOffset(index: 1, episodes: items), (167.0, 119.0, 100.0));
    expect(calcItemHeight(EpisodeItem()), 112);
  });
  test('尾项定位在视口内且倒序短列表不产生负偏移', () {
    expect(
      adjustScrollOffset(offset: 567, remain: 100, viewportDimension: 500),
      279,
    );
    expect(
      adjustScrollOffset(
        offset: 100,
        remain: 7,
        viewportDimension: 500,
        isReversed: true,
      ),
      0,
    );
    expect(
      calcPageItemOffset(index: 9, itemCount: 10, viewportDimension: 500),
      1000,
    );
    expect(
      calcPageItemOffsetSeparated(
        index: 9,
        itemCount: 10,
        extent: 140,
        separator: 10,
        viewportDimension: 500,
      ),
      990,
    );
  });
}
