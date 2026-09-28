import 'package:PiliPlus/common/widgets/selection_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget customMenuBuilder(BuildContext context, SelectableRegionState state) {
  return const SizedBox.shrink();
}

void main() {
  testWidgets('普通文本默认使用站内搜索菜单', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SelectionText('测试文字')));

    final selectionArea = tester.widget<SelectionArea>(
      find.byType(SelectionArea),
    );
    expect(selectionArea.contextMenuBuilder, same(openUrlMenuBuilder));
  });

  testWidgets('富文本保留调用者自定义菜单', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SelectionText.rich(
          TextSpan(text: '测试文字'),
          contextMenuBuilder: customMenuBuilder,
        ),
      ),
    );

    final selectionArea = tester.widget<SelectionArea>(
      find.byType(SelectionArea),
    );
    expect(selectionArea.contextMenuBuilder, same(customMenuBuilder));
  });
}
