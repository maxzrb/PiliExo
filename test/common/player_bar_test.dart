import 'package:PiliPlus/common/widgets/player_bar.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/bottom_control.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/translation_subtitle_picker.dart';
import 'package:flutter/material.dart' hide VerticalDivider;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' show VerticalDivider;

class _BottomBarPlayer extends Fake implements PlPlayerController {
  @override
  final showControls = true.obs;
  @override
  final buffered = 0.obs;
  @override
  final duration = 60.obs;
  @override
  final progress = 0;
  @override
  final enableBlock = false;
  @override
  final showViewPoints = false;
}

class _BottomBarPage extends Fake implements VideoDetailController {
  @override
  final showDmTrendChart = false.obs;
  @override
  final switchingAudioLanguage = false.obs;
  @override
  final currLang = Rxn<String>();
  @override
  final vttSubtitlesIndex = 0.obs;
  @override
  final isVertical = true.obs;
  @override
  final subtitles = [Subtitle(id: 1, lan: 'zh', lanDoc: '简体中文')].obs;
  final _languages = Rx<List<({String code, String title})>>(const [
    (code: '', title: '原声'),
    (code: 'en', title: 'English（AI）'),
  ]);
  @override
  List<({String code, String title})> get audioLanguageOptions =>
      _languages.value;

  @override
  Future<void> setLanguage(String language) async => currLang.value = language;

  @override
  Future<void> setSubtitle(int index) async => vttSubtitlesIndex.value = index;
}

void main() {
  testWidgets('视频详情返回时底栏立即显示分集控件', (tester) async {
    final detail = VideoDetailData().obs;
    await tester.pumpWidget(
      MaterialApp(
        home: BottomControl(
          maxWidth: 600,
          isFullScreen: false,
          controller: _BottomBarPlayer(),
          videoDetailController: _BottomBarPage(),
          buildBottomControl: () => Row(
            children: [
              if (detail.value.hasParts) ...[
                const Text('上一集'),
                const Text('下一集'),
                const Text('选集'),
              ],
              const Text('配音语言'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('配音语言'), findsOneWidget);
    expect(find.text('选集'), findsNothing);
    detail.value = VideoDetailData(pages: [Part(cid: 1), Part(cid: 2)]);
    await tester.pump();

    expect(find.text('上一集'), findsOneWidget);
    expect(find.text('下一集'), findsOneWidget);
    expect(find.text('选集'), findsOneWidget);
  });

  testWidgets('底栏空间不足时隐藏可选控件，放得下时可点击', (tester) async {
    final dubbing = find.semantics.byLabel('翻译与字幕');
    final compact = find.semantics.byLabel('字幕');
    const fullButton = Key('full-picker');
    const fitButton = Key('fit');
    var taps = 0;

    Widget bar(double width) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: Align(
          alignment: Alignment.topLeft,
          child: PlayerBar(
            left: const SizedBox(width: 100, height: 30),
            rightLeading: const SizedBox(width: 20, height: 30),
            right: const SizedBox(key: fitButton, width: 130, height: 30),
            compactRight: Semantics(
              label: '字幕',
              textDirection: TextDirection.ltr,
              child: const SizedBox(width: 30, height: 30),
            ),
            optionalRight: Semantics(
              key: fullButton,
              label: '翻译与字幕',
              textDirection: TextDirection.ltr,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 35, height: 30),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(bar(284));
    expect(dubbing, findsNothing);
    expect(compact, findsOne);
    await tester.tapAt(const Offset(130, 15));
    expect(taps, 0);

    await tester.pumpWidget(bar(285));
    expect(dubbing, findsOne);
    expect(compact, findsNothing);
    expect(
      tester.getRect(find.byKey(fullButton)).right,
      tester.getRect(find.byKey(fitButton)).left,
    );
    await tester.tapAt(const Offset(130, 15));
    expect(taps, 1);

    await tester.pumpWidget(bar(240));
    expect(dubbing, findsNothing);
    expect(compact, findsOne);
    await tester.tapAt(const Offset(130, 15));
    expect(taps, 1);
  });

  testWidgets('翻译与字幕左右分栏并分别选中', (tester) async {
    final page = _BottomBarPage();
    await tester.pumpWidget(
      MaterialApp(
        home: TranslationSubtitlePanel(controller: page),
      ),
    );
    final dubbing = find.text('English（AI）');
    final caption = find.text('简体中文');
    expect(
      tester.getCenter(dubbing).dx,
      lessThan(tester.getCenter(caption).dx),
    );
    expect(find.byType(VerticalDivider), findsOneWidget);
    await tester.tap(dubbing);
    await tester.pump();
    expect(page.currLang.value, 'en');
    expect(page.vttSubtitlesIndex.value, 0);
    await tester.tap(caption);
    await tester.pump();
    expect(page.currLang.value, 'en');
    expect(page.vttSubtitlesIndex.value, 1);
  });

  testWidgets('竖屏有空间仍用统一图标，窄栏只在同款面板显示字幕', (tester) async {
    final page = _BottomBarPage();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Row(
              children: [
                TranslationSubtitleButton(
                  key: const Key('wide'),
                  controller: page,
                  width: 35,
                ),
                TranslationSubtitleButton(
                  key: const Key('compact'),
                  controller: page,
                  width: 35,
                  includeDubbing: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.closed_caption_outlined), findsNWidgets(2));
    expect(find.byType(PopupMenuButton), findsNothing);

    await tester.tap(find.byKey(const Key('compact')));
    await tester.pumpAndSettle();
    expect(find.byType(TranslationSubtitlePanel), findsOneWidget);
    expect(find.text('翻译与字幕'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('配音语言'), findsNothing);
    expect(find.byType(VerticalDivider), findsNothing);
    Get.back<void>();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wide')));
    await tester.pumpAndSettle();
    expect(find.byType(TranslationSubtitlePanel), findsOneWidget);
    expect(find.text('翻译与字幕'), findsOneWidget);
    expect(find.text('配音语言'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsOneWidget);
  });
}
