import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';

enum DynamicsUpPanelSlot { all, search, me }

abstract final class DynamicsUpNavigation {
  static const int allMid = -1;
  static const int searchMid = -2;

  /// 固定入口顺序：全部动态、搜索关注、我。
  static const List<DynamicsUpPanelSlot> fixedPanelSlots = [
    DynamicsUpPanelSlot.all,
    DynamicsUpPanelSlot.search,
    DynamicsUpPanelSlot.me,
  ];

  static int tabIndexFor(int mid) {
    return mid == allMid ? DynamicsTabType.all.index : DynamicsTabType.up.index;
  }
}
