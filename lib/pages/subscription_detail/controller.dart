import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/sub/sub/list.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/data.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/media.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/common/page_order/page_order_mixin.dart';
import 'package:get/get.dart';

class SubDetailController
    extends CommonListController<SubDetailData, SubDetailItemModel>
    with PageOrderMixin {
  late int id;
  String? heroTag;
  SubItemModel? subInfo;
  bool _orderInitialized = false;

  @override
  int get count => subInfo?.mediaCount ?? 0;

  @override
  int get ps => _ps;
  static const _ps = 20;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    id = args['id'];
    subInfo = args['subInfo'];
    heroTag = args['heroTag'];

    if (count != 0) {
      _orderInitialized = true;
      updatePageOrderOnly(true);
      page = 1;
    }
    queryData();
  }

  @override
  List<SubDetailItemModel>? getDataList(SubDetailData response) {
    subInfo = response.info;
    return response.medias;
  }

  @override
  void checkIsEnd(int length) {
    if (pageDesc) {
      if (page == 1) isEnd = true;
    } else {
      final count = subInfo?.mediaCount;
      if (count != null && length >= count) {
        isEnd = true;
      }
    }
  }

  Future<LoadingState<SubDetailData>> fetchPage({
    required int pn,
    bool pageDesc = false,
  }) => FavHttp.favSeasonList(id: id, ps: _ps, pn: pn, pageDesc: pageDesc);

  @override
  Future<LoadingState<SubDetailData>> customGetData() async {
    if (!_orderInitialized) {
      // 直接入口没有总数时，先获取元信息，再定位倒序的最后一页。
      final first = await fetchPage(pn: 1);
      if (first case Success(:final response)) {
        subInfo = response.info ?? subInfo;
        _orderInitialized = true;
        if (count > 0) {
          updatePageOrderOnly(true);
          page = 1;
          if (page == 1) {
            response.medias = response.medias?.reversed.toList();
            return first;
          }
        } else {
          return first;
        }
      } else {
        return first;
      }
    }
    return fetchPage(pn: page, pageDesc: pageDesc);
  }
}
