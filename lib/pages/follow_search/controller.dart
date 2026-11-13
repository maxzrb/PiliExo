import 'package:PiliPlus/http/follow.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/member.dart';
import 'package:PiliPlus/models_new/follow/data.dart';
import 'package:PiliPlus/models_new/follow/list.dart';
import 'package:PiliPlus/pages/common/search/common_search_controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/followed_up_search.dart';
import 'package:easy_debounce/easy_debounce.dart';

class FollowSearchController
    extends CommonSearchController<FollowData, FollowItemModel> {
  FollowSearchController(this.mid, {this.localFuzzy = false});
  final int mid;
  final bool localFuzzy;

  final List<FollowItemModel> _allFollowed = [];
  bool _allFollowedLoaded = false;

  String get _debounceKey => 'followSearchLocal_${mid}_$hashCode';

  @override
  String get searchHint => localFuzzy ? '搜索关注的UP主' : super.searchHint;

  @override
  void onInit() {
    super.onInit();
    if (localFuzzy) {
      editController.addListener(_onQueryChanged);
      onRefresh();
    }
  }

  @override
  Future<LoadingState<FollowData>> customGetData() async {
    if (localFuzzy) {
      if (!_allFollowedLoaded) {
        final result = await _loadAllFollowed();
        if (result case Error()) return result;
      }
      final items = FollowedUpSearch.filter(
        items: _allFollowed,
        query: editController.text,
        nameOf: (item) => item.uname ?? '',
      );
      isEnd = true;
      return Success(FollowData(list: items, total: items.length));
    }
    return MemberHttp.getfollowSearch(
      mid: mid,
      ps: 20,
      pn: page,
      name: editController.value.text,
    );
  }

  Future<LoadingState<FollowData>> _loadAllFollowed() async {
    const pageSize = 50;
    final mids = _allFollowed.map((item) => item.mid).toSet();
    var page = 1;
    while (true) {
      final res = await FollowHttp.followings(
        vmid: Accounts.main.mid,
        pn: page,
        ps: pageSize,
        orderType: 'attention',
      );
      if (res case Error()) return res;

      final response = res.data;
      final data = response.list ?? const <FollowItemModel>[];
      for (final item in data) {
        if (mids.add(item.mid)) {
          _allFollowed.add(item);
        }
      }
      final total = response.total;
      if (data.isEmpty ||
          data.length < pageSize ||
          (total != null && page * pageSize >= total)) {
        _allFollowedLoaded = true;
        break;
      }
      page++;
    }
    return Success(FollowData(list: _allFollowed, total: _allFollowed.length));
  }

  void _onQueryChanged() {
    EasyDebounce.debounce(
      _debounceKey,
      const Duration(milliseconds: 180),
      () {
        if (!isClosed) onRefresh();
      },
    );
  }

  @override
  List<FollowItemModel>? getDataList(FollowData response) {
    return response.list;
  }

  @override
  Future<void> onRefresh() {
    if (!localFuzzy) return super.onRefresh();
    page = 1;
    isEnd = false;
    loadingState.value = LoadingState.loading();
    return queryData();
  }

  @override
  void onClose() {
    if (localFuzzy) {
      editController.removeListener(_onQueryChanged);
      EasyDebounce.cancel(_debounceKey);
    }
    super.onClose();
  }
}
