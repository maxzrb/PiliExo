abstract final class GalleryLivePhoto {
  static const int none = -1;
  static const int preloadRadius = 1;

  /// 当前页及相邻页提前挂载到静态封面下方，先完成纹理创建和首帧上传。
  static bool shouldMountVideo({
    required int pageIndex,
    required int currentIndex,
  }) {
    return (pageIndex - currentIndex).abs() <= preloadRadius;
  }

  /// 只有当前页和已经完成首帧准备的 Live Photo 才能显示视频层。
  static bool shouldShowVideo({
    required int pageIndex,
    required int currentIndex,
    required int readyIndex,
  }) {
    return pageIndex == currentIndex && currentIndex == readyIndex;
  }
}
