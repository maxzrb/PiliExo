import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/video_status_bar_ambient.dart';
import 'package:PiliPlus/plugin/pl_player/models/ambient_frame.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> message() => {
    'format': 'rgba8888',
    'width': 2,
    'height': 1,
    'rowBytes': 8,
    'pixels': Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]),
  };

  test('原始RGBA保持红绿通道顺序和图像大小', () async {
    final frame = AmbientRgbaFrame.fromMessage(message())!;
    final image = await frame.toImage();
    try {
      expect((image.width, image.height), (2, 1));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes!.buffer.asUint8List(), frame.pixels);
    } finally {
      image.dispose();
    }
  });

  test('允许行末填充且不会当成下一行像素', () async {
    final frame = AmbientRgbaFrame.fromMessage({
      'format': 'rgba8888',
      'width': 1,
      'height': 2,
      'rowBytes': 8,
      'pixels': Uint8List.fromList([
        255,
        0,
        0,
        255,
        9,
        9,
        9,
        9,
        0,
        255,
        0,
        255,
        9,
        9,
        9,
        9,
      ]),
    })!;
    final image = await frame.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = bytes!.buffer.asUint8List();
      expect((image.width, image.height), (1, 2));
      // 引擎读回可能保留行跨度，只核对两行实际像素，不能把填充当成像素。
      expect(rgba.sublist(0, 4), [255, 0, 0, 255]);
      expect(rgba.sublist(rgba.length - 4), [0, 255, 0, 255]);
    } finally {
      image.dispose();
    }
  });

  test('拒绝错误格式、尺寸、行跨度和截断数据', () {
    for (final values in [
      <String, Object>{'format': 'bgra8888'},
      <String, Object>{'width': 0},
      <String, Object>{'height': 257},
      <String, Object>{'rowBytes': 4},
      <String, Object>{'pixels': Uint8List(7)},
    ]) {
      expect(AmbientRgbaFrame.fromMessage({...message(), ...values}), isNull);
    }
    expect(AmbientRgbaFrame.fromMessage(null), isNull);
  });

  const texture = AmbientTextureFrame(
    textureId: 17,
    viewportSize: Size(400, 300),
    videoSize: Size(1920, 1080),
    fit: BoxFit.contain,
    alignment: Alignment.center,
    fill: Color(0xff000000),
    flipX: true,
    flipY: false,
  );

  testWidgets('环境纹理复用指定ID并保留视口、镜像和顶部裁剪', (tester) async {
    final images = ValueNotifier<ui.Image?>(null);
    final textures = ValueNotifier<AmbientTextureFrame?>(texture);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 30,
            child: VideoStatusBarAmbient(frame: images, texture: textures),
          ),
        ),
      ),
    );
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 17);
    final boxes = tester.widgetList<FittedBox>(find.byType(FittedBox)).toList();
    expect(boxes.first.fit, BoxFit.cover);
    expect(boxes.first.alignment, Alignment.topCenter);
    expect(boxes.last.fit, BoxFit.contain);
    expect(find.byType(ClipRect), findsNWidgets(2));
    textures.value = null;
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
    await tester.pumpWidget(const SizedBox());
    images.dispose();
    textures.dispose();
  });
}
