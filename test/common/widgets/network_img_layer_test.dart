import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('按铺满卡片所需像素解码并复用图像', (tester) async {
    final cache = _ImageFiles();
    CachedNetworkImageProvider.defaultCacheManager = cache;

    final directory = Directory.systemTemp.createTempSync('cover-decode-');
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      directory.deleteSync(recursive: true);
    });

    const sourceSizes = [(240, 120), (120, 240), (40, 20)];
    const decodedSizes = [(200, 100), (100, 200), (40, 20)];
    for (final (index, (width, height)) in sourceSizes.indexed) {
      final url = 'https://example.test/thumbnail-$index.png';
      final file = File('${directory.path}/$index.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(width, height);
        picture.dispose();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        image.dispose();
        await file.writeAsBytes(bytes.buffer.asUint8List());
      });
      cache.files[url] = file;

      Widget tree() => MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: NetworkImgLayer(
              src: url,
              width: 50,
              height: 50,
              quality: 100,
              getPlaceHolder: () => const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        final provider = tester.widget<Image>(find.byType(Image)).image;
        final rendered = Completer<void>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (info, _) {
            info.dispose();
            rendered.complete();
          },
          onError: rendered.completeError,
        );
        stream.addListener(listener);
        try {
          await rendered.future.timeout(const Duration(seconds: 4));
        } finally {
          stream.removeListener(listener);
        }
      });
      await tester.pumpAndSettle();

      final image = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect((image?.width, image?.height), decodedSizes[index]);
      expect(cache.accesses.where((access) => access == url), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();
      expect(cache.accesses.where((access) => access == url), hasLength(1));
    }
  });
}

class _ImageFiles extends Fake implements BaseCacheManager {
  final files = <String, File>{};
  final accesses = <String>[];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    accesses.add(url);
    return Stream.value(
      FileInfo(files[url]!, FileSource.Cache, DateTime.now(), url),
    );
  }
}
