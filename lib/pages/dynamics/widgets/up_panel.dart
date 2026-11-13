import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/follow_search/view.dart';
import 'package:PiliPlus/pages/live_follow/view.dart';
import 'package:PiliPlus/pages/share/view.dart' show UserModel;
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/dynamics_up_navigation.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class UpPanel extends StatefulWidget {
  const UpPanel({
    super.key,
    required this.upData,
    required this.dynamicsController,
  });

  final FollowUpModel upData;
  final DynamicsController dynamicsController;

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  late final controller = widget.dynamicsController;
  late final isTop = controller.upPanelPosition == UpPanelPosition.top;
  UpItem? _searchedUp;

  void toFollowPage() => Get.to(const LiveFollowPage());

  Future<void> _searchFollowedUp() async {
    final selected = await Get.to<UserModel>(
      FollowSearchPage(
        mid: Accounts.main.mid,
        isFromSelect: true,
        localFuzzy: true,
      ),
    );
    if (!mounted || selected == null) return;
    _onSelect(
      UpItem(
        mid: selected.mid,
        uname: selected.name,
        face: selected.avatar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upData = widget.upData;
    final sourceUpList = upData.upList;
    final searchedUp = _searchedUp;
    final upList = <UpItem>[
      if (searchedUp != null &&
          !(sourceUpList?.any((item) => item.mid == searchedUp.mid) ?? false))
        searchedUp,
      ...?sourceUpList,
    ];
    final liveList = upData.liveUsers?.items;
    return CustomScrollView(
      scrollDirection: isTop ? .horizontal : .vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      controller: controller.scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: InkWell(
            onTap: () => setState(() {
              controller.showLiveUp = !controller.showLiveUp;
            }),
            onLongPress: toFollowPage,
            onSecondaryTap: PlatformUtils.isMobile ? null : toFollowPage,
            child: Container(
              alignment: .center,
              height: isTop ? 76 : 60,
              padding: isTop ? const .only(left: 12, right: 6) : null,
              child: Text.rich(
                textAlign: .center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Live(${upData.liveUsers?.count ?? 0})',
                    ),
                    if (!isTop) ...[
                      const TextSpan(text: '\n'),
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          controller.showLiveUp
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ] else
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          controller.showLiveUp
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_left,
                          color: theme.colorScheme.primary,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (controller.showLiveUp && liveList != null && liveList.isNotEmpty)
          SliverList.builder(
            itemCount: liveList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, liveList[index]);
            },
          ),
        ...DynamicsUpNavigation.fixedPanelSlots.map(
          (slot) => switch (slot) {
            DynamicsUpPanelSlot.all => SliverToBoxAdapter(
              child: upItemBuild(
                theme,
                UpItem(
                  face: '',
                  uname: '全部动态',
                  mid: DynamicsUpNavigation.allMid,
                ),
              ),
            ),
            DynamicsUpPanelSlot.search => SliverToBoxAdapter(
              child: upItemBuild(
                theme,
                UpItem(
                  face: '',
                  uname: '搜索UP',
                  mid: DynamicsUpNavigation.searchMid,
                ),
              ),
            ),
            DynamicsUpPanelSlot.me => SliverToBoxAdapter(
              child: Obx(
                () => upItemBuild(
                  theme,
                  UpItem(
                    uname: '我',
                    face: controller.accountService.face.value,
                    mid: Accounts.main.mid,
                  ),
                ),
              ),
            ),
          },
        ),
        if (upList.isNotEmpty)
          SliverList.builder(
            itemCount: upList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, upList[index]);
            },
          ),
        if (!isTop) const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  void _onSelect(UpItem item) {
    item.hasUpdate = false;
    _searchedUp =
        item.mid == DynamicsUpNavigation.allMid || item.mid == Accounts.main.mid
        ? null
        : widget.upData.upList?.firstWhereOrNull(
                (followedUp) => followedUp.mid == item.mid,
              ) ??
              item;
    controller.onSelectUp(item.mid);
    setState(() {});
  }

  Widget upItemBuild(ThemeData theme, UpItem item) {
    final currentMid = controller.currentMid;
    final isLive = item is LiveUserItem;
    final isSearch = item.mid == DynamicsUpNavigation.searchMid;
    final isCurrent = isLive || currentMid == item.mid || currentMid == -1;

    final isAll = item.mid == DynamicsUpNavigation.allMid;
    void toMemberPage() => Get.toNamed('/member?mid=${item.mid}');

    Widget avatar;
    if (isAll) {
      avatar = DecoratedBox(
        decoration: const BoxDecoration(
          shape: .circle,
          color: Color(0xFF5CB67B),
        ),
        child: Image.asset(
          width: 38,
          height: 38,
          cacheWidth: 38.cacheSize(context),
          Assets.logo2,
          color: Colors.white,
        ),
      );
    } else if (isSearch) {
      avatar = DecoratedBox(
        decoration: BoxDecoration(
          shape: .circle,
          color: theme.colorScheme.secondaryContainer,
        ),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            Icons.search_outlined,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      );
    } else {
      avatar = Padding(
        padding: const .symmetric(horizontal: 4),
        child: NetworkImgLayer(
          width: 38,
          height: 38,
          src: item.face,
          type: .avatar,
        ),
      );
      if (isLive) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: isLive && !isTop ? -5 : 0,
              right: -6,
              child: Badge(
                label: const Text(' Live '),
                textColor: theme.colorScheme.onSecondaryContainer,
                backgroundColor: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.75),
              ),
            ),
          ],
        );
      } else if (item.hasUpdate ?? false) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: 0,
              right: 4,
              child: Badge(
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        );
      }
    }

    return SizedBox(
      height: 76,
      width: isTop ? 70 : null,
      child: InkWell(
        onTap: () {
          feedBack();
          if (isSearch) {
            _searchFollowedUp();
          } else if (isLive) {
            PageUtils.toLiveRoom(item.roomId);
          } else {
            _onSelect(item);
          }
        },
        // onDoubleTap: isLive ? () => _onSelect(data) : null,
        onLongPress: !isAll && !isSearch ? toMemberPage : null,
        onSecondaryTap: !isAll && !isSearch && !PlatformUtils.isMobile
            ? toMemberPage
            : null,
        child: Opacity(
          opacity: isCurrent ? 1 : 0.6,
          child: Column(
            spacing: 4,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              avatar,
              Padding(
                padding: const .symmetric(horizontal: 4),
                child: Text(
                  isTop ? '${item.uname}\n' : item.uname!,
                  maxLines: 2,
                  textAlign: .center,
                  overflow: .ellipsis,
                  style: TextStyle(
                    color: currentMid == item.mid
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    height: 1.1,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
