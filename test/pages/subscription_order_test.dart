import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/sub/sub/list.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/data.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/media.dart';
import 'package:PiliPlus/pages/subscription_detail/controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends SubDetailController {
  final requests = <(int, bool)>[];
  final int total;
  _Controller(this.total);

  @override
  Future<LoadingState<SubDetailData>> fetchPage({
    required int pn,
    bool pageDesc = false,
  }) async {
    requests.add((pn, pageDesc));
    final ids = List.generate(total, (i) => i + 1).skip((pn - 1) * 20).take(20);
    return Success(
      SubDetailData(
        info: SubItemModel(mediaCount: total),
        medias: (pageDesc ? ids.toList().reversed : ids)
            .map((id) => SubDetailItemModel(id: id))
            .toList(),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('未知数量入口先读取总数，再倒序跨页且不重复条目', () async {
    final controller = _Controller(45);
    addTearDown(controller.onClose);
    await controller.queryData();
    await controller.onLoadMore();
    await controller.onLoadMore();
    await controller.onLoadMore();
    final items =
        (controller.loadingState.value as Success<List<SubDetailItemModel>?>)
            .response!;
    expect(items.map((e) => e.id), List.generate(45, (i) => 45 - i));
    expect(controller.requests, [(1, false), (3, true), (2, true), (1, true)]);
    expect(controller.isEnd, isTrue);
    await controller.onRefresh();
    expect(controller.requests.last, (3, true));
  });
  test('单页直接入口无需重复请求，切换正序重新从第一页开始', () async {
    final controller = _Controller(3);
    addTearDown(controller.onClose);
    await controller.queryData();
    expect(controller.requests, [(1, false)]);
    expect(controller.pageDesc, isTrue);
    expect(
      (controller.loadingState.value as Success<List<SubDetailItemModel>?>)
          .response!
          .map((e) => e.id),
      [3, 2, 1],
    );
    controller.updatePageOrderOnly(false);
    await controller.onRefresh();
    expect(controller.requests.last, (1, false));
    expect(
      (controller.loadingState.value as Success<List<SubDetailItemModel>?>)
          .response!
          .map((e) => e.id),
      [1, 2, 3],
    );
  });
}
