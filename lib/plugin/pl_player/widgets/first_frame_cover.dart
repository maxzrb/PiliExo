import 'package:flutter/widgets.dart';

/// 纹理已分配尺寸但还未提交首帧时，保留播放器底色。
class FirstFrameCover extends StatelessWidget {
  const FirstFrameCover({
    super.key,
    required this.firstFrame,
    required this.color,
    required this.child,
  });

  final Future<void> firstFrame;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: firstFrame,
    builder: (context, snapshot) => Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (snapshot.connectionState != ConnectionState.done)
          Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: color)),
          ),
      ],
    ),
  );
}
