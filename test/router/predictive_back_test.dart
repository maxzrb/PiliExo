import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart' show popScope;
import 'package:PiliPlus/common/widgets/image_viewer/hero_dialog_route.dart';
import 'package:PiliPlus/router/app_page_route.dart';
import 'package:PiliPlus/router/page_transitions.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const _home = '首页';
const _detail = '详情';
const _field = ValueKey('详情输入');

Finder _transitionPart(Finder page, String key) => find.ancestor(
  of: page,
  matching: find.byKey(ValueKey(key), skipOffstage: false),
);

Future<void> _sendBackGesture(WidgetTester tester, MethodCall call) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(call),
      (_) {},
    );

Future<void> _startGesture(
  WidgetTester tester, {
  int swipeEdge = 0,
}) => _sendBackGesture(
  tester,
  MethodCall('startBackGesture', {
    'touchOffset': const <double>[5, 300],
    'progress': 0.0,
    'swipeEdge': swipeEdge,
  }),
);

Future<void> _moveGesture(
  WidgetTester tester, {
  int swipeEdge = 0,
  double progress = 0.45,
}) async {
  await _sendBackGesture(
    tester,
    MethodCall('updateBackGestureProgress', {
      'touchOffset': const <double>[160, 300],
      'progress': progress,
      'swipeEdge': swipeEdge,
    }),
  );
  await tester.pump();
}

Future<void> _finishGesture(WidgetTester tester, String method) async {
  await _sendBackGesture(tester, MethodCall(method));
  await tester.pumpAndSettle();
}

Future<void> _launch(
  WidgetTester tester, {
  int? transition,
  PredictiveBackStyle style = PredictiveBackStyle.followGesture,
  bool predictiveBack = true,
  int slidePercent = 50,
  int fadePercent = 100,
  int scalePercent = 20,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      initialRoute: '/',
      themeMode: ThemeMode.light,
      builder: FlutterSmartDialog.init(),
      navigatorObservers: [FlutterSmartDialog.observer],
      onGenerateRoute: AppPageRoute.generate,
      onInit: () {
        PageTransitions.selectStyleIndex(style.index);
        PageTransitions.selectMotion(
          slidePercent: slidePercent,
          fadePercent: fadePercent,
          scalePercent: scalePercent,
        );
        PageTransitions.select(transition ?? Transition.native.index);
        PageTransitions.setEnabled(predictiveBack, androidSdkInt: 34);
        Get.addPages([
          GetPage(
            name: '/',
            page: () => const Scaffold(body: Text(_home)),
          ),
          GetPage(
            name: '/details',
            page: () => Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_detail ${Get.parameters['id']}: ${Get.arguments}'),
                  const TextField(key: _field),
                ],
              ),
            ),
          ),
        ]);
      },
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('预测性返回仅在 Android 14 及以上生效', () {
    PageTransitions.setEnabled(true, androidSdkInt: 33);
    expect(PageTransitions.predictiveBack.value, isFalse);
    PageTransitions.setEnabled(true, androidSdkInt: 34);
    expect(PageTransitions.predictiveBack.value, isTrue);
    PageTransitions.setEnabled(false, androidSdkInt: 34);
    expect(PageTransitions.predictiveBack.value, isFalse);
  });

  testWidgets('普通进页时背景留在原位且不重挂载', (tester) async {
    await _launch(tester);
    final home = find.text(_home, skipOffstage: false);
    final homeElement = tester.element(home);
    final position = tester.getTopLeft(home);

    unawaited(Get.toNamed<void>('/details?id=1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.element(home), same(homeElement));
    expect(tester.getTopLeft(home), position);
    await tester.pumpAndSettle();
  });

  testWidgets('开始及取消预测性返回时页面内容不脱离组件树', (tester) async {
    await _launch(tester, style: PredictiveBackStyle.zoomFade);
    var deactivations = 0;
    unawaited(
      AppPageRoute.push<void>(
        _TrackedPage(onDeactivate: () => deactivations++),
      ),
    );
    await tester.pumpAndSettle();

    await _startGesture(tester);
    await _moveGesture(tester);
    expect(deactivations, 0);

    await _finishGesture(tester, 'cancelBackGesture');
    expect(deactivations, 0);
    expect(find.text(_detail), findsOneWidget);
  });

  for (final losesFocus in [true, false]) {
    final interruption = losesFocus ? '系统浮层使窗口失焦' : '没有失焦通知时收到新的触摸';
    testWidgets('页面渐隐返回被打断后恢复点击：$interruption', (tester) async {
      await _launch(tester, style: PredictiveBackStyle.fade);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var taps = 0;
      unawaited(
        AppPageRoute.push<void>(
          Scaffold(
            body: TextButton(
              onPressed: () => taps++,
              child: const Text(_detail),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final detail = find.text(_detail);
      final opacity = _transitionPart(detail, 'predictive-back-opacity');
      final navigator = Get.key.currentState!;

      await _startGesture(tester);
      await _moveGesture(tester);
      expect(navigator.userGestureInProgress, isTrue);
      expect(find.text(_home), findsOneWidget);
      expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));

      if (losesFocus) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else {
        // 系统已放弃手势但没发取消回调，第一下触摸会结束残留预览。
        await tester.tapAt(tester.getCenter(detail));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(navigator.userGestureInProgress, isFalse);
      if (losesFocus) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      expect(find.text(_home), findsNothing);
      expect(tester.widget<Opacity>(opacity).opacity, 1);

      // 迟到的提交属于被打断的手势，不能在恢复操作后退出当前页。
      await _finishGesture(tester, 'commitBackGesture');
      await tester.tap(detail);
      expect(taps, 1);
      await _startGesture(tester);
      await _moveGesture(tester);
      await _finishGesture(tester, 'commitBackGesture');
      expect(detail, findsNothing);
      expect(find.text(_home), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);
    });
  }

  testWidgets('返回预览圆角随手势出现，取消复原且松手时连续', (tester) async {
    await _launch(tester, style: PredictiveBackStyle.zoomFade);
    unawaited(Get.toNamed<void>('/details?id=7'));
    await tester.pumpAndSettle();

    final detail = find.text('详情 7: null');
    final clip = _transitionPart(detail, 'predictive-back-corners');
    ClipRRect corners() => tester.widget<ClipRRect>(clip);
    double radius() =>
        corners().borderRadius.resolve(TextDirection.ltr).topLeft.x;

    expect(radius(), 0);
    expect(corners().clipBehavior, Clip.none);

    await _startGesture(tester);
    await _moveGesture(tester);
    expect(radius(), greaterThan(20));
    expect(corners().clipBehavior, Clip.antiAlias);

    await _finishGesture(tester, 'cancelBackGesture');
    expect(radius(), 0);
    expect(corners().clipBehavior, Clip.none);

    await _startGesture(tester);
    await _moveGesture(tester);
    final beforeRelease = radius();
    await _sendBackGesture(tester, const MethodCall('commitBackGesture'));
    await tester.pump();
    expect(radius(), closeTo(beforeRelease, 0.01));
    await tester.pump(const Duration(milliseconds: 90));
    expect(radius(), greaterThan(beforeRelease));

    await tester.pumpAndSettle();
    expect(detail, findsNothing);
  });

  testWidgets('预测性返回拖动期间逐帧调度，取消和提交后停止', (tester) async {
    await _launch(tester, style: PredictiveBackStyle.zoomFade);
    unawaited(Get.toNamed<void>('/details?id=1'));
    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
    for (final finish in ['cancelBackGesture', 'commitBackGesture']) {
      await _startGesture(tester);
      await _moveGesture(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 11));
        expect(tester.binding.hasScheduledFrame, isTrue);
      }

      await _finishGesture(tester, finish);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('跟手方向中背景页逆着左右手势镜像归位', (tester) async {
    await _launch(tester);
    final background = _transitionPart(
      find.text(_home, skipOffstage: false),
      'predictive-back-corners',
    );
    final center = tester.getCenter(background).dx;
    unawaited(Get.toNamed<void>('/details?id=4'));
    await tester.pumpAndSettle();
    final foreground = _transitionPart(
      find.text('详情 4: null'),
      'predictive-back-corners',
    );

    for (final (edge, direction) in [(0, 1), (1, -1)]) {
      await _startGesture(tester, swipeEdge: edge);
      await _moveGesture(tester, swipeEdge: edge, progress: 0.25);
      final early = tester.getCenter(background).dx;
      expect((early - center) * direction, greaterThan(0));

      await _moveGesture(tester, swipeEdge: edge, progress: 0.6);
      final late = tester.getCenter(background).dx;
      expect((late - early) * direction, lessThan(0));
      expect(
        (tester.getCenter(foreground).dx - center) * direction,
        greaterThan(0),
      );

      if (edge == 0) {
        await _finishGesture(tester, 'cancelBackGesture');
      } else {
        await _sendBackGesture(tester, const MethodCall('commitBackGesture'));
        await tester.pump();
        expect(tester.getCenter(background).dx, closeTo(late, 0.01));
        await tester.pumpAndSettle();
      }
      expect(tester.getCenter(background).dx, center);
    }
  });

  testWidgets('半程松手时背景继续放大并轻微回弹', (tester) async {
    await _launch(tester, style: PredictiveBackStyle.alwaysRight);
    unawaited(Get.toNamed<void>('/details?id=1'));
    await tester.pumpAndSettle();

    await _startGesture(tester);
    await _moveGesture(tester);
    double backgroundScale() => tester
        .widget<Transform>(
          _transitionPart(find.text(_home), 'predictive-back-covered-scale'),
        )
        .transform
        .entry(0, 0);

    final releasedFrom = backgroundScale();
    expect(releasedFrom, lessThan(0.99));
    final backgroundCorners = _transitionPart(
      find.text(_home),
      'predictive-back-corners',
    );
    expect(
      tester.widget<ClipRRect>(backgroundCorners).clipBehavior,
      Clip.antiAlias,
    );
    await _sendBackGesture(tester, const MethodCall('commitBackGesture'));
    await tester.pump();
    expect(backgroundScale(), closeTo(releasedFrom, 0.001));

    await tester.pump(const Duration(milliseconds: 90));
    expect(backgroundScale(), greaterThan(releasedFrom));
    expect(backgroundScale(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(backgroundScale(), greaterThan(1));

    await tester.pumpAndSettle();
    expect(backgroundScale(), 1);
  });

  testWidgets('命名页面随手势预览，取消后保留内容，完成时返回上一页', (tester) async {
    await _launch(
      tester,
      transition: Transition.native.index,
      predictiveBack: false,
    );
    unawaited(Get.toNamed<void>('/details?id=42', arguments: '参数'));
    await tester.pumpAndSettle();

    final detail = find.text('详情 42: 参数');
    await tester.enterText(find.byKey(_field), '保留这段文字');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    PageTransitions.setEnabled(true, androidSdkInt: 34);
    await tester.pumpAndSettle();
    final original = tester.getTopLeft(detail);
    await _startGesture(tester);
    await tester.pump();
    await _moveGesture(tester);
    expect(tester.getTopLeft(detail).dx, greaterThan(original.dx));
    expect(find.text(_home), findsOneWidget);

    await _finishGesture(tester, 'cancelBackGesture');
    expect(tester.getTopLeft(detail), original);
    expect(find.text('保留这段文字'), findsOneWidget);

    await _startGesture(tester);
    await _moveGesture(tester);
    await _finishGesture(tester, 'commitBackGesture');
    expect(detail, findsNothing);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('直接打开的页面先处理局部返回，再允许预测性返回', (tester) async {
    await _launch(tester);
    final blocked = ValueNotifier(true);
    addTearDown(blocked.dispose);
    final result = AppPageRoute.push<int>(
      ValueListenableBuilder(
        valueListenable: blocked,
        builder: (context, isBlocked, child) => popScope(
          canPop: !isBlocked,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) blocked.value = false;
          },
          child: child!,
        ),
        child: const Scaffold(body: Text(_detail)),
      ),
    );
    await tester.pumpAndSettle();

    await _startGesture(tester);
    await _finishGesture(tester, 'commitBackGesture');
    expect(blocked.value, isFalse);
    expect(find.text(_detail), findsOneWidget);

    await _startGesture(tester);
    await _moveGesture(tester);
    expect(find.text(_home), findsOneWidget);
    await _finishGesture(tester, 'cancelBackGesture');
    Get.back(result: 42);
    await tester.pumpAndSettle();
    expect(await result, 42);
  });

  testWidgets('全屏图片可预览返回，浮层打开时先关闭浮层', (tester) async {
    await _launch(tester);
    unawaited(
      Get.key.currentState!.push<void>(
        HeroDialogRoute(
          pageBuilder: (_, _, _) => const Scaffold(body: Text(_detail)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(SmartDialog.show<void>(builder: (_) => const Text('浮层')));
    await tester.pumpAndSettle();

    await _startGesture(tester);
    await _finishGesture(tester, 'commitBackGesture');
    expect(find.text('浮层'), findsNothing);
    expect(find.text(_detail), findsOneWidget);

    final detail = find.text(_detail);
    final original = tester.getTopLeft(detail);
    await _startGesture(tester);
    await _moveGesture(tester);
    expect(tester.getTopLeft(detail).dx, greaterThan(original.dx));
    await _finishGesture(tester, 'commitBackGesture');
    expect(detail, findsNothing);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('预测性返回支持明显位移、固定方向与页面渐隐', (tester) async {
    await _launch(tester, style: PredictiveBackStyle.alwaysRight);
    unawaited(Get.toNamed<void>('/details?id=1'));
    await tester.pumpAndSettle();
    final detail = find.text('详情 1: null');
    final original = tester.getTopLeft(detail);
    final pageWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final minimumDistance = pageWidth * 0.35;
    final maximumDistance = pageWidth * 0.5 + 1;

    await _startGesture(tester);
    await _moveGesture(tester);
    final rightDistance = tester.getTopLeft(detail).dx - original.dx;
    expect(rightDistance, greaterThan(minimumDistance));
    expect(rightDistance, lessThanOrEqualTo(maximumDistance));
    await _finishGesture(tester, 'cancelBackGesture');

    PageTransitions.selectStyleIndex(PredictiveBackStyle.alwaysLeft.index);
    await tester.pumpAndSettle();
    await _startGesture(tester);
    await _moveGesture(tester);
    final leftDistance = original.dx - tester.getTopLeft(detail).dx;
    expect(leftDistance, greaterThan(minimumDistance));
    expect(leftDistance, lessThanOrEqualTo(maximumDistance));
    await _finishGesture(tester, 'cancelBackGesture');

    PageTransitions.selectStyleIndex(PredictiveBackStyle.fade.index);
    await tester.pumpAndSettle();
    await _startGesture(tester);
    await _moveGesture(tester);
    final opacity = tester.widget<Opacity>(
      _transitionPart(detail, 'predictive-back-opacity'),
    );
    expect(opacity.opacity, lessThan(0.65));
    expect(tester.getTopLeft(detail).dx, original.dx);
    await _finishGesture(tester, 'cancelBackGesture');

    PageTransitions.selectMotion(fadePercent: 0);
    await tester.pumpAndSettle();
    await _startGesture(tester);
    await _moveGesture(tester);
    expect(
      tester
          .widget<Opacity>(
            _transitionPart(detail, 'predictive-back-opacity'),
          )
          .opacity,
      1,
    );
    await _finishGesture(tester, 'cancelBackGesture');

    PageTransitions.selectStyleIndex(PredictiveBackStyle.zoomFade.index);
    PageTransitions.selectMotion(fadePercent: 100);
    await tester.pumpAndSettle();
    await _startGesture(tester);
    await _moveGesture(tester);
    final zoomOpacity = tester.widget<Opacity>(
      _transitionPart(detail, 'predictive-back-opacity'),
    );
    final zoomTransform = tester.widget<Transform>(
      _transitionPart(detail, 'predictive-back-scale'),
    );
    expect(zoomOpacity.opacity, lessThan(0.65));
    expect(zoomTransform.transform.entry(0, 0), lessThan(0.95));
    await _finishGesture(tester, 'cancelBackGesture');

    PageTransitions.selectStyleIndex(PredictiveBackStyle.followGesture.index);
    await tester.pumpAndSettle();
    await _startGesture(tester, swipeEdge: 1);
    await _moveGesture(tester, swipeEdge: 1);
    expect(
      original.dx - tester.getTopLeft(detail).dx,
      greaterThan(minimumDistance),
    );
  });

  testWidgets('松手后从当前预览位置继续，不会重置后再播一遍', (tester) async {
    await _launch(tester, style: PredictiveBackStyle.alwaysRight);
    unawaited(Get.toNamed<void>('/details?id=2'));
    await tester.pumpAndSettle();
    final detail = find.text('详情 2: null');
    final original = tester.getTopLeft(detail);
    final pageWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await _startGesture(tester);
    await _moveGesture(tester);
    final previewDistance = tester.getTopLeft(detail).dx - original.dx;
    expect(previewDistance, greaterThan(100));

    await _sendBackGesture(tester, const MethodCall('commitBackGesture'));
    await tester.pump();
    final commitDistance = tester.getTopLeft(detail).dx - original.dx;
    expect(commitDistance, greaterThanOrEqualTo(previewDistance - 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.getTopLeft(detail).dx - original.dx,
      greaterThan(commitDistance),
    );
    // 松手后必须把页面送出整屏，而不是停在设定比例后被路由销毁。
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.getTopLeft(detail).dx - original.dx,
      greaterThan(pageWidth * 0.9),
    );

    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('位移与渐隐幅度可调，衬底跟随深色主题和纯黑设置', (tester) async {
    const darkBackdrop = Color(0xFF202125);
    final previousTheme = ThemeUtils.darkTheme;
    addTearDown(() => ThemeUtils.darkTheme = previousTheme);
    ThemeUtils.darkTheme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: darkBackdrop,
    );
    await _launch(
      tester,
      style: PredictiveBackStyle.alwaysRight,
      slidePercent: 100,
      fadePercent: 0,
    );
    unawaited(Get.toNamed<void>('/details?id=3'));
    await tester.pumpAndSettle();
    final detail = find.text('详情 3: null');
    final original = tester.getTopLeft(detail);
    final pageWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await _startGesture(tester);
    await _moveGesture(tester);
    final wideDistance = tester.getTopLeft(detail).dx - original.dx;
    expect(wideDistance, greaterThan(pageWidth * 0.75));
    final wideOpacity = tester.widget<Opacity>(
      _transitionPart(detail, 'predictive-back-opacity'),
    );
    expect(wideOpacity.opacity, 1);
    final coveredScale = tester.widget<Transform>(
      _transitionPart(find.text(_home), 'predictive-back-covered-scale'),
    );
    expect(coveredScale.transform.entry(0, 0), lessThan(0.99));
    final backing = find.byKey(const ValueKey('predictive-back-background'));
    expect(tester.widget<ColoredBox>(backing).color, darkBackdrop);
    expect(tester.getRect(backing), Offset.zero & tester.getSize(backing));
    expect(tester.getSize(backing).width, pageWidth);
    await _finishGesture(tester, 'cancelBackGesture');
    expect(backing, findsNothing);

    ThemeUtils.darkTheme = ThemeUtils.darkenTheme(ThemeUtils.darkTheme);
    PageTransitions.selectMotion(slidePercent: 30, fadePercent: 80);
    // 切换页面过渡动画不应关闭已经开启的预测性返回。
    PageTransitions.select(Transition.fade.index);
    await tester.pumpAndSettle();
    await _startGesture(tester);
    await _moveGesture(tester);
    expect(tester.widget<ColoredBox>(backing).color, Colors.black);
    final narrowDistance = tester.getTopLeft(detail).dx - original.dx;
    expect(narrowDistance, greaterThan(pageWidth * 0.2));
    expect(narrowDistance, lessThanOrEqualTo(pageWidth * 0.3 + 1));
    final fadedOpacity = tester.widget<Opacity>(
      _transitionPart(detail, 'predictive-back-opacity'),
    );
    expect(fadedOpacity.opacity, closeTo(1 - 0.8 * 0.45, 0.02));
    await _finishGesture(tester, 'cancelBackGesture');
  });
}

class _TrackedPage extends StatefulWidget {
  const _TrackedPage({required this.onDeactivate});

  final VoidCallback onDeactivate;

  @override
  State<_TrackedPage> createState() => _TrackedPageState();
}

class _TrackedPageState extends State<_TrackedPage> {
  @override
  void deactivate() {
    widget.onDeactivate();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text(_detail));
}
