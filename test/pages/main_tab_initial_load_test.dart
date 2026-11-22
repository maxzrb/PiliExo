import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/mine_tab_type.dart';
import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics_tab/controller.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('main-tab-load-');
    Hive.init(directory.path);
    GStorage.regAdapter();
    GStorage.setting = await Hive.openBox('setting');
    GStorage.userInfo = await Hive.openBox<UserInfoData>('userInfo');
    await GStorage.setting.putAll({
      SettingBoxKey.enableSearchWord: true,
      SettingBoxKey.hideTopBar: false,
    });
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  final input = jsonDecode(
    File(
      'test/fixtures/main_tab_initial_load/input.json',
    ).readAsStringSync(encoding: utf8),
  ) as List;
  final reference = jsonDecode(
    File(
      'test/ref/fate/main-tab-initial-load',
    ).readAsStringSync(encoding: utf8),
  ) as List;

  for (final (index, sample) in input.indexed) {
    testWidgets('固定样例：${sample['name']}', (tester) async {
      await tester.runAsync(() async {
        await GStorage.setting.put(
          SettingBoxKey.mineTabs,
          (sample['mineTabs'] as List)
              .map((name) => MineTabType.values.byName(name as String).index)
              .toList(),
        );
        if (sample['cachedUser'] as bool) {
          await GStorage.userInfo.put('userInfoCache', UserInfoData(mid: 42));
        } else {
          await GStorage.userInfo.delete('userInfoCache');
        }
      });

      final requests = <String>[];
      final account = Get.put(AccountService());
      late final _Recommendations recommendations;
      late final _Mine mine;
      final actual = <List<String>>[];
      try {
        for (final event in sample['events'] as List) {
          switch (event) {
            case 'mount':
              Get.put<HomeController>(_Home(requests));
              recommendations = Get.put(_Recommendations(requests));
              Get
                ..put<DynamicsController>(_Dynamics(requests))
                ..put(_DynamicsTab(requests));
              mine = Get.put(_Mine(requests));
            case 'frame':
              tester.binding.scheduleFrame();
              await tester.pump();
            case 'logout':
              account.isLogin.value = false;
            case 'closeMine':
              Get.delete<_Mine>();
            case 'refreshRecommendations':
              await recommendations.onRefresh();
            default:
              fail('未知测试事件 $event');
          }
          actual.add(requests.toList());
          requests.clear();
        }
        expect(actual, reference[index]);
        if (sample['cachedUser'] == true && account.isLogin.value) {
          expect(mine.userInfo.value.mid, 42);
        }
      } finally {
        Get.reset();
      }
    });
  }
}

class _Home extends HomeController {
  _Home(this.requests);
  final List<String> requests;

  @override
  Future<void> querySearchDefault() =>
      Future.sync(() => requests.add('search'));
}

class _Recommendations extends RcmdController {
  _Recommendations(this.requests);
  final List<String> requests;

  @override
  Future<LoadingState<List<int>>> customGetData() async {
    requests.add('recommendations');
    return const Success([42]);
  }
}

class _Dynamics extends DynamicsController {
  _Dynamics(this.requests);
  final List<String> requests;

  @override
  Future<void> queryData([bool isRefresh = true]) =>
      Future.sync(() => requests.add('following'));

  @override
  void onChangeAccount(bool isLogin) {}
}

class _DynamicsTab extends DynamicsTabController {
  _DynamicsTab(this.requests) : super(dynamicsType: DynamicsTabType.all);
  final List<String> requests;

  @override
  Future<void> queryData([bool isRefresh = true]) =>
      Future.sync(() => requests.add('feed'));

  @override
  void onChangeAccount(bool isLogin) {}
}

class _Mine extends MineController {
  _Mine(this.requests);
  final List<String> requests;

  @override
  void onInit() {
    super.onInit();
    if (favCtr case final original?) {
      original.onDelete();
      favCtr = _Favorite(requests);
    }
    if (historyCtr case final original?) {
      original.onDelete();
      historyCtr = _History(requests);
    }
  }

  @override
  Future<void> queryUserInfo() => Future.sync(() => requests.add('user'));
}

class _Favorite extends FavCtr {
  _Favorite(this.requests);
  final List<String> requests;

  @override
  Future<void> queryData([bool isRefresh = true]) =>
      Future.sync(() => requests.add('favorite'));
}

class _History extends HistoryCtr {
  _History(this.requests);
  final List<String> requests;

  @override
  Future<void> queryData([bool isRefresh = true]) =>
      Future.sync(() => requests.add('history'));
}
