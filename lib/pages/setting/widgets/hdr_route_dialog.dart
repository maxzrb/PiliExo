import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/models/hdr_playback_route.dart';
import 'package:material_ui/material_ui.dart';

Future<HdrPlaybackRoute?> showHdrRouteDialog(
  BuildContext context, {
  required HdrPlaybackRoute value,
  bool currentVideo = false,
}) => showDialog<HdrPlaybackRoute>(
  context: context,
  builder: (context) => SelectDialog<HdrPlaybackRoute>(
    title: currentVideo ? '当前视频的 HDR 路线' : 'HDR 播放路线',
    value: value,
    values: HdrPlaybackRoute.values.map((e) => (e, e.title)).toList(),
    subtitleBuilder: (context, index) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Text(HdrPlaybackRoute.values[index].details),
    ),
  ),
);
