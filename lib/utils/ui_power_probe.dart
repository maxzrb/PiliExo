import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/common/widgets/frosted_surface.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// 显式研究包在同一缓存列表上进行开销归因，不写入持久设置。
abstract final class UiPowerProbe {
  static const enabled = bool.fromEnvironment('PILI_UI_POWER_PROBE');
  static const compareUniform = bool.fromEnvironment(
    'PILI_UI_POWER_COMPARE_UNIFORM',
  );
  static bool _started = false;

  static void start() {
    if (!enabled || _started) return;
    _started = true;
    unawaited(_run());
  }

  static void _event(String event, Map<String, Object?> values) => debugPrint(
    'PILI_UI_POWER ${jsonEncode({
      'event': event,
      'epochMs': DateTime.now().millisecondsSinceEpoch,
      ...values,
    })}',
  );

  static Future<void> _run() async {
    final original = FrostedSurfaceConfig.notifier.value;
    final timings = <FrameTiming>[];
    void record(List<FrameTiming> values) => timings.addAll(values);
    ScrollController? scroll;
    double? originalOffset;
    String? label;
    final binding = SchedulerBinding.instance;
    bool active() {
      if (binding.lifecycleState != AppLifecycleState.resumed ||
          Get.currentRoute != '/') {
        return false;
      }
      final main = Get.find<MainController>();
      final home = Get.find<HomeController>();
      return main.navigationBars[main.selectedIndex.value] ==
              NavigationBarType.home &&
          home.tabs[home.tabController.index] == HomeTabType.rcmd;
    }

    Future<void> wait(Duration duration) async {
      await Future<void>.delayed(duration);
      if (!active()) throw StateError('前台页面已变化，研究取消');
    }

    binding.addTimingsCallback(record);
    try {
      await wait(const Duration(seconds: 12));
      scroll = Get.find<HomeController>().scrollController;
      if (!scroll.hasClients || scroll.position.maxScrollExtent < 600) {
        throw StateError('推荐列表尚未加载到足够长度');
      }
      originalOffset = scroll.offset;
      // 只移动已缓存的前几张卡片，不触发翻页和下拉刷新。
      for (var index = 0; index < 2; index++) {
        await scroll.animateTo(
          550,
          duration: const Duration(milliseconds: 700),
          curve: Curves.linear,
        );
        await scroll.animateTo(
          100,
          duration: const Duration(milliseconds: 700),
          curve: Curves.linear,
        );
      }
      _event('start', {
        'originalFrosted': original.enabled,
        'style': original.style.name,
        'viewport': scroll.position.viewportDimension,
      });
      for (final moving in [false, true]) {
        for (var index = 0; index < 4; index++) {
          final variantA = index == 0 || index == 3;
          final frosted = compareUniform || variantA;
          label =
              '${moving ? 'scroll' : 'idle'}-${index + 1}-${variantA ? 'A' : 'B'}';
          FrostedSurfaceConfig.update(
            enabled: frosted,
            optimizeUniformBackground: compareUniform
                ? !variantA
                : original.optimizeUniformBackground,
          );
          scroll.jumpTo(100);
          await wait(const Duration(seconds: 2));
          timings.clear();
          _event('phase_start', {
            'label': label,
            'frosted': frosted,
            'optimizedUniformBackground':
                FrostedSurfaceConfig.notifier.value.optimizeUniformBackground,
            'compareUniform': compareUniform,
            'moving': moving,
            'offset': scroll.offset,
          });
          final clock = Stopwatch()..start();
          var cycles = 0;
          if (moving) {
            for (; cycles < 10; cycles++) {
              await scroll.animateTo(
                550,
                duration: const Duration(milliseconds: 700),
                curve: Curves.linear,
              );
              await wait(const Duration(milliseconds: 150));
              await scroll.animateTo(
                100,
                duration: const Duration(milliseconds: 700),
                curve: Curves.linear,
              );
              await wait(const Duration(milliseconds: 150));
            }
          }
          final remaining = const Duration(seconds: 20) - clock.elapsed;
          if (remaining > Duration.zero) await wait(remaining);
          // 回调可能批量延迟投递，边界保留约1秒，分析时排除首尾CPU样本。
          final builds =
              timings
                  .map((value) => value.buildDuration.inMicroseconds)
                  .toList()
                ..sort();
          final rasters =
              timings
                  .map((value) => value.rasterDuration.inMicroseconds)
                  .toList()
                ..sort();
          int? p95(List<int> values) => values.isEmpty
              ? null
              : values[((values.length - 1) * .95).floor()];
          _event('phase_end', {
            'label': label,
            'frosted': frosted,
            'moving': moving,
            'offset': scroll.offset,
            'cycles': cycles,
            'durationMs': clock.elapsedMilliseconds,
            'frames': timings.length,
            'buildP95Us': p95(builds),
            'rasterP95Us': p95(rasters),
            'buildOver8333Us': builds.where((value) => value > 8333).length,
            'rasterOver8333Us': rasters.where((value) => value > 8333).length,
          });
        }
      }
      _event('complete', {});
    } catch (error) {
      _event('aborted', {'label': label, 'reason': error.toString()});
    } finally {
      binding.removeTimingsCallback(record);
      FrostedSurfaceConfig.update(
        enabled: original.enabled,
        style: original.style,
        optimizeUniformBackground: original.optimizeUniformBackground,
      );
      if (scroll != null &&
          scroll.hasClients &&
          originalOffset != null &&
          active()) {
        scroll.jumpTo(originalOffset.clamp(0, scroll.position.maxScrollExtent));
      }
    }
  }
}
