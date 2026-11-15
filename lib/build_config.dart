abstract final class BuildConfig {
  // 缺少构建参数时不能把历史默认值当成真实已安装版本，尤其不能触发旧签名迁移。
  static const bool hasReleaseMetadata =
      bool.hasEnvironment('pili.name') &&
      bool.hasEnvironment('pili.releaseBuild') &&
      bool.hasEnvironment('pili.code');

  // versionCode 是 Android 安装版本号，必须按正式 Release 全局递增，不能按日期重置。
  static const int versionCode = int.fromEnvironment(
    'pili.code',
    defaultValue: 8,
  );

  // releaseBuild 是 vYY.M.D.N 中当天的发布序号，与 Android versionCode 分开维护。
  static const int releaseBuild = int.fromEnvironment(
    'pili.releaseBuild',
    defaultValue: 2,
  );

  static const String versionName = String.fromEnvironment(
    'pili.name',
    defaultValue: '26.8.30',
  );

  static const int buildTime = int.fromEnvironment('pili.time');
  static const String commitHash = String.fromEnvironment(
    'pili.hash',
    defaultValue: 'N/A',
  );

  static String get displayVersion =>
      hasReleaseMetadata ? '$versionName+$releaseBuild' : '本地构建（未写入版本信息）';
}
