import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;

/// 楼中楼加载进度。
///
/// [loaded] 必须是按回复 id 去重后的数量；[total] 是服务端报告的总数。
/// 服务端总数可能缺失或被后续页覆盖成 0，调用方应先合并总数再传入。
double replyLoadProgress({
  required int loaded,
  required int total,
  required bool isEnd,
}) {
  if (isEnd) return 1;
  if (loaded <= 0 || total <= 0) return 0;
  return (loaded / total).clamp(0.0, 1.0);
}

/// 合并分页返回的总数。
///
/// 刷新时采用服务端新值；非刷新页只允许总数增大，避免后续页缺少
/// `root.count` 时把总数覆盖成 0，导致进度条停在原地。
int mergeReplyTotal({
  required int previous,
  required int incoming,
  required bool isRefresh,
}) {
  if (isRefresh) return incoming;
  return incoming > previous ? incoming : previous;
}

/// 统计已加载回复的唯一 id 数量。
///
/// 分页之间可能出现重复回复；直接使用列表长度会把进度算超。
int uniqueReplyCount(Iterable<ReplyInfo>? replies) =>
    replies?.map((reply) => reply.id).toSet().length ?? 0;

/// 用当前已加载高度估算整条楼中楼的总高度。
///
/// 只在首屏/第一页建立一次估算，后续加载不再改变分母。
/// [total] 是服务端总数；未知时按已加载页数处理。
double estimateReplyTotalExtent({
  required double loadedExtent,
  required int loadedPages,
  required int total,
}) {
  if (loadedExtent <= 0 || loadedPages <= 0) return 0;
  final pages = total > 0 ? (total + 19) ~/ 20 : loadedPages;
  return loadedExtent / loadedPages * pages;
}

/// 楼中楼滚动进度。
///
/// 分母是固定的估算总高度，分子只随滚动偏移变化。这样增量加载时
/// 进度不会因为列表变长而闪动或后退。
double replyScrollProgress({
  required double pixels,
  required double estimatedTotalExtent,
}) {
  if (estimatedTotalExtent <= 0) return 0;
  return (pixels / estimatedTotalExtent).clamp(0.0, 1.0);
}
