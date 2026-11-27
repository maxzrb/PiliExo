import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class RecommendFilter {
  static int minDurationForRcmd = Pref.minDurationForRcmd;
  static int minPlayForRcmd = Pref.minPlayForRcmd;
  static int minLikeRatioForRecommend = Pref.minLikeRatioForRecommend;
  static bool exemptFilterForFollowed = Pref.exemptFilterForFollowed;
  static bool applyFilterToRelatedVideos = Pref.applyFilterToRelatedVideos;
  static RegExp rcmdRegExp = RegExp(
    Pref.banWordForRecommend,
    caseSensitive: false,
  );
  static bool enableFilter = rcmdRegExp.pattern.isNotEmpty;
  static RegExp upNameRegExp = RegExp(
    Pref.banWordForRecommendUpName,
    caseSensitive: false,
  );
  static Set<int> blockedMids = Pref.recommendBlockedMids.toSet();
  static Set<int> allowedMids = Pref.recommendAllowedMids.toSet();

  static bool filterWithExempt(
    BaseVideoItemModel videoItem, {
    bool zoneMatches = false,
  }) => _filterVideo(
    videoItem,
    followedExempt: videoItem.isFollowed && exemptFilterForFollowed,
    zoneMatches: zoneMatches,
  );

  /// hot/rank/[filterAll]
  static bool filterLikeRatio(int? like, int? view) {
    if (view != null) {
      return (view > -1 && view < minPlayForRcmd) ||
          (like != null &&
              like > -1 &&
              like * 100 < minLikeRatioForRecommend * view);
    }
    return false;
  }

  /// hot/rank/[filterAll]
  static bool filterTitle(String title) {
    return (enableFilter && rcmdRegExp.hasMatch(title));
  }

  /// [filterAll]
  static bool filterDuration(int duration) {
    return duration > 0 && duration < minDurationForRcmd;
  }

  /// related/[filterWithExempt]
  static bool filterAll(
    BaseVideoItemModel videoItem, {
    bool zoneMatches = false,
  }) => _filterVideo(videoItem, zoneMatches: zoneMatches);

  static bool _filterVideo(
    BaseVideoItemModel videoItem, {
    bool followedExempt = false,
    required bool zoneMatches,
  }) {
    final owner = videoItem.owner;
    if (blockedMids.contains(owner.mid)) return true;
    if (followedExempt || allowedMids.contains(owner.mid)) return false;
    return zoneMatches ||
        filterDuration(videoItem.duration) ||
        filterLikeRatio(videoItem.stat.like, videoItem.stat.view) ||
        filterTitle(videoItem.title) ||
        (upNameRegExp.pattern.isNotEmpty &&
            upNameRegExp.hasMatch(owner.name ?? ''));
  }
}
