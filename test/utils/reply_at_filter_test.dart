import 'package:PiliPlus/utils/reply_at_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('纯@评论允许尾随空格、换行及多个已知用户', () {
    for (final message in ['@用户甲', '@用户甲 ', ' @用户甲\n@用户乙\t', '@用户甲@用户乙']) {
      expect(
        isMentionOnlyReply(message, ['用户甲', '用户乙']),
        isTrue,
        reason: message,
      );
    }
  });
  test('普通正文、未知用户和只有空白不被误屏蔽', () {
    for (final message in [
      '',
      ' ',
      '@用户甲 看这个',
      '看看@用户甲',
      '@陌生用户',
      '@用户甲额外文字',
    ]) {
      expect(isMentionOnlyReply(message, ['用户甲']), isFalse, reason: message);
    }
  });
  test('按完整用户名匹配，支持重叠名字、空格和表情', () {
    expect(
      isMentionOnlyReply('@foo bar @foo😀 ', ['foo', 'foo bar', 'foo😀']),
      isTrue,
    );
    expect(isMentionOnlyReply('@foobar', ['foo']), isFalse);
  });
  test('楼中楼只在存在回复前缀时跳过前缀', () {
    expect(
      isMentionOnlyReply('回复 @楼主: @用户甲 ', ['用户甲'], hasReplyPrefix: true),
      isTrue,
    );
    expect(
      isMentionOnlyReply('普通文字 @用户甲', ['用户甲'], hasReplyPrefix: true),
      isFalse,
    );
    expect(
      isMentionOnlyReply('回复 @楼主: 普通文字 @用户甲', ['用户甲'], hasReplyPrefix: true),
      isFalse,
    );
  });
}
