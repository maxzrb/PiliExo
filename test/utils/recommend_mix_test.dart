import 'package:PiliPlus/utils/recommend_mix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('推荐比例会吸附到 10% 步进并限制范围', () {
    expect(RecommendMix.normalizeRatio(-1), 0);
    expect(RecommendMix.normalizeRatio(34), 30);
    expect(RecommendMix.normalizeRatio(36), 40);
    expect(RecommendMix.normalizeRatio(120), 100);
    expect(RecommendMix.normalizeRatio(null, fallback: 20), 20);
  });

  test('混合推荐说明下一次刷新生效，而不是重启生效', () {
    expect(
      RecommendMix.describeRatio(70, pending: true),
      'App 70% · Web 30%（下次刷新生效）',
    );
    expect(RecommendMix.describeRatio(70), 'App 70% · Web 30%');
  });

  test('Web 和 App 端点只返回对应来源', () {
    const app = ['a1', 'a2', 'a3'];
    const web = ['w1', 'w2', 'w3'];

    expect(
      RecommendMix.mix(
        app: app,
        web: web,
        appRatio: 0,
        keyOf: (item) => item,
        maxItems: 10,
      ),
      web,
    );
    expect(
      RecommendMix.mix(
        app: app,
        web: web,
        appRatio: 100,
        keyOf: (item) => item,
        maxItems: 10,
      ),
      app,
    );
  });

  test('混合推荐按比例交错并去重', () {
    final result = RecommendMix.mix(
      app: List.generate(10, (index) => 'a$index'),
      web: List.generate(10, (index) => 'w$index'),
      appRatio: 70,
      keyOf: (item) => item,
      maxItems: 10,
    );

    expect(result.length, 10);
    expect(result.where((item) => item.startsWith('a')).length, 7);
    expect(result.where((item) => item.startsWith('w')).length, 3);
  });

  test('重复视频不会因为两路来源合并而重复显示', () {
    final result = RecommendMix.mix(
      app: const ['a1', 'same', 'a2'],
      web: const ['w1', 'same', 'w2'],
      appRatio: 50,
      keyOf: (item) => item,
      maxItems: 6,
    );

    expect(result, ['a1', 'w1', 'same', 'a2', 'w2']);
    expect(result.toSet().length, result.length);
  });
}
