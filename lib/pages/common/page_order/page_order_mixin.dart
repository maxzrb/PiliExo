import 'package:PiliPlus/pages/common/common_list_controller.dart';

mixin PageOrderMixin<R, T> on CommonListController<R, T> {
  int get ps;
  int get count;

  bool _pageDesc = false;
  bool get pageDesc => _pageDesc;

  @override
  // 倒序从最后一页开始，后续请求向前翻页。
  set page(int value) {
    if (pageDesc) {
      if (value == 1) {
        super.page = (count / ps).ceil();
      } else {
        super.page--;
      }
    } else {
      super.page = value;
    }
  }

  void updatePageOrder(bool value) {
    if (updatePageOrderOnly(value)) return;
    onReload();
  }

  bool updatePageOrderOnly(bool value) {
    if (count == 0) return true;
    _pageDesc = value;
    return false;
  }
}
