abstract final class BuildConfig {
  // 未传入发布元数据时，使用 pubspec.yaml 当前正式版本，避免本地构建显示为 SNAPSHOT。
  static const int versionCode = int.fromEnvironment(
    'pili.code',
    defaultValue: 1,
  );
  static const String versionName = String.fromEnvironment(
    'pili.name',
    defaultValue: '26.8.29',
  );

  static const int buildTime = int.fromEnvironment('pili.time');
  static const String commitHash = String.fromEnvironment(
    'pili.hash',
    defaultValue: 'N/A',
  );
}
