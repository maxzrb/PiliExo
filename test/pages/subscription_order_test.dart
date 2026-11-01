import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/data.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/media.dart';
import 'package:PiliPlus/pages/subscription_detail/controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends SubDetailController {
  final requests = <(int, bool)>[];
  final Map<String, dynamic> pages;
  _Controller(this.pages);

  @override
  Future<LoadingState<SubDetailData>> fetchPage({
    required int pn,
    bool pageDesc = false,
  }) async {
    requests.add((pn, pageDesc));
    return Success(SubDetailData.fromJson(pages['$pn'], pageDesc: pageDesc));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final input = jsonDecode(
    File('test/fixtures/upstream_220/input.json').readAsStringSync(),
  )['subscriptions'];
  final reference = jsonDecode(
    File('test/fixtures/upstream_220/reference.json').readAsStringSync(),
  )['subscriptions'];
  test('未知数量入口先读取总数，再倒序跨页且不重复条目', () async {
    final controller = _Controller(input['many']['pages']);
    addTearDown(controller.onClose);
    await controller.queryData();
    for (var i = 0; i < input['many']['loadMore']; i++) {
      await controller.onLoadMore();
    }
    final items =
        (controller.loadingState.value as Success<List<SubDetailItemModel>?>)
            .response!;
    expect(items.map((e) => e.id), reference['many']['ids']);
    expect(
      controller.requests.map((r) => [r.$1, r.$2]).toList(),
      reference['many']['requests'],
    );
    expect(controller.isEnd, reference['many']['isEnd']);
    await controller.onRefresh();
    expect([
      controller.requests.last.$1,
      controller.requests.last.$2,
    ], reference['many']['afterRefreshRequest']);
  });
  test('单页直接入口无需重复请求，切换正序重新从第一页开始', () async {
    final controller = _Controller(input['single']['pages']);
    addTearDown(controller.onClose);
    await controller.queryData();
    expect(
      controller.requests.map((r) => [r.$1, r.$2]).toList(),
      reference['single']['requests'],
    );
    expect(controller.pageDesc, isTrue);
    expect(
      (controller.loadingState.value as Success<List<SubDetailItemModel>?>)
          .response!
          .map((e) => e.id),
      reference['single']['ids'],
    );
    controller.updatePageOrderOnly(false);
    await controller.onRefresh();
    expect([
      controller.requests.last.$1,
      controller.requests.last.$2,
    ], reference['single']['afterOrderRequest']);
    expect(
      (controller.loadingState.value as Success<List<SubDetailItemModel>?>)
          .response!
          .map((e) => e.id),
      reference['single']['afterOrderIds'],
    );
  });
}
