abstract final class RecommendMix {
  static const int minAppRatio = 0;
  static const int maxAppRatio = 100;
  static const int ratioStep = 10;
  static const int defaultAppRatio = 100;

  /// 将推荐来源比例限制为 0～100，并吸附到 10% 的步进。
  static int normalizeRatio(Object? value, {int fallback = defaultAppRatio}) {
    final fallbackValue = _snap(fallback.toDouble()).toDouble();
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) {
      return _snap(fallbackValue);
    }
    return _snap(parsed.toDouble());
  }

  /// 返回设置页中显示的推荐来源说明。
  static String describeRatio(int appRatio) {
    final ratio = normalizeRatio(appRatio);
    return switch (ratio) {
      0 => 'Web 推荐（纯 Web）',
      100 => 'App 推荐（纯 App）',
      _ => 'App $ratio% · Web ${100 - ratio}%（重启后生效）',
    };
  }

  /// 按 App 比例交错合并两路推荐，并按视频 key 去重。
  ///
  /// [maxItems] 是本次刷新交给列表的最大数量。两路推荐均成功时，
  /// 使用加权轮转让返回列表尽量接近目标比例；一侧耗尽或为空时，
  /// 会自动使用另一侧的剩余内容。
  static List<T> mix<T>({
    required List<T> app,
    required List<T> web,
    required int appRatio,
    required String Function(T item) keyOf,
    int maxItems = 20,
  }) {
    final ratio = normalizeRatio(appRatio);
    final limit = maxItems.clamp(0, 1 << 30).toInt();
    if (limit == 0) return const [];

    if (ratio == 0 || app.isEmpty) {
      return _takeDistinct(web, limit, keyOf);
    }
    if (ratio == 100 || web.isEmpty) {
      return _takeDistinct(app, limit, keyOf);
    }

    final merged = <T>[];
    final seen = <String>{};
    var appIndex = 0;
    var webIndex = 0;
    var appCredit = 0;
    var webCredit = 0;

    while (merged.length < limit &&
        (appIndex < app.length || webIndex < web.length)) {
      final hasApp = appIndex < app.length;
      final hasWeb = webIndex < web.length;
      late final T item;

      if (!hasWeb || (hasApp && appCredit >= webCredit)) {
        item = app[appIndex++];
        appCredit -= 100;
      } else {
        item = web[webIndex++];
        webCredit -= 100;
      }

      if (hasApp && hasWeb) {
        appCredit += ratio;
        webCredit += 100 - ratio;
      }
      if (seen.add(keyOf(item))) {
        merged.add(item);
      }
    }
    return merged;
  }

  static List<T> _takeDistinct<T>(
    List<T> source,
    int limit,
    String Function(T item) keyOf,
  ) {
    final result = <T>[];
    final seen = <String>{};
    for (final item in source) {
      if (seen.add(keyOf(item))) {
        result.add(item);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  static int _snap(double value) {
    final clamped = value.isFinite
        ? value.clamp(minAppRatio, maxAppRatio).toDouble()
        : defaultAppRatio.toDouble();
    return ((clamped / ratioStep).round() * ratioStep)
        .clamp(minAppRatio, maxAppRatio)
        .toInt();
  }
}
