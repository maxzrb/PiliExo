import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/widgets.dart' show GlobalKey, ScrollController;
import 'package:get/get.dart';

mixin ScrollOrRefreshMixin {
  ScrollController get scrollController;

  /// 绑定与当前列表配套的下拉刷新动画。
  final refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  void animateToTop() => scrollController.animToTop();

  Future<void> onRefresh();

  /// 以程序化方式显示下拉刷新动画并执行原有刷新回调。
  Future<void> refreshWithIndicator() {
    return refreshIndicatorKey.currentState?.show() ?? onRefresh();
  }

  /// 点击当前导航项时，回到顶部或以带动画的方式刷新。
  void toTopOrRefreshWithIndicator() {
    if (scrollController.hasClients) {
      if (scrollController.position.pixels == 0) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          refreshWithIndicator,
        );
      } else {
        animateToTop();
      }
    }
  }

  void toTopOrRefresh() {
    if (scrollController.hasClients) {
      if (scrollController.position.pixels == 0) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          onRefresh,
        );
      } else {
        animateToTop();
      }
    }
  }
}

abstract class CommonController<R, T> extends GetxController
    with ScrollOrRefreshMixin {
  @override
  final ScrollController scrollController = ScrollController();

  bool isLoading = false;
  Rx<LoadingState> get loadingState;

  Future<LoadingState<R>> customGetData();

  Future<void> queryData([bool isRefresh = true]);

  bool customHandleResponse(bool isRefresh, Success<R> response) {
    return false;
  }

  bool handleError(String? errMsg) {
    return false;
  }

  @override
  Future<void> onRefresh() {
    return queryData();
  }

  Future<void> onLoadMore() {
    return queryData(false);
  }

  Future<void> onReload() {
    return onRefresh();
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}
