import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/common/widgets/refresh_indicator.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/article_content_model.dart' as opus;
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:PiliPlus/utils/app_sign.dart';
import 'package:PiliPlus/utils/scroll_offset_helper.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/video_link_progress.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Replies extends ReplyController<MainListReply> {
  _Replies(this.pages);
  final List pages;
  int requests = 0;
  @override
  int get oid => 1;
  @override
  int get replyType => 1;
  @override
  dynamic get sourceId => null;
  @override
  List<ReplyInfo> getDataList(MainListReply response) => response.replies;
  @override
  Future<LoadingState<MainListReply>> customGetData() async {
    final page = pages[requests++];
    return Success(
      MainListReply(
        replies: (page['ids'] as List).map((id) => ReplyInfo(id: Int64(id))),
        cursor: CursorReply(isEnd: page['end']),
        paginationReply: FeedPaginationReply(nextOffset: page['offset']),
        subjectControl: SubjectControl(count: Int64(100)),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final input = jsonDecode(
    File('test/fixtures/upstream_20261104/input.json').readAsStringSync(
      encoding: utf8,
    ),
  );
  final reference = jsonDecode(
    File('test/fixtures/upstream_20261104/reference.json').readAsStringSync(
      encoding: utf8,
    ),
  );
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('upstream-20261104-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('固定样例：签名保留空值等号与重复键', () {
    final samples = input['sign'] as List;
    final actual = samples.map((sample) {
      final params = Map<String, dynamic>.from(sample['params']);
      params['list'] = (params['list'] as List).cast<String>();
      AppSign.appSign(
        params,
        appkey: 'test-app',
        appsec: 'test-secret',
        timestamp: sample['timestamp'],
      );
      return params['sign'];
    }).toList();
    expect(actual, reference['sign']);
  });

  test('固定样例：弹幕提前定位与显式起点优先级', () {
    expect(
      (input['progress'] as List)
          .map(
            (sample) =>
                parseVideoLinkProgress(Map<String, String>.from(sample)),
          )
          .toList(),
      reference['progress'],
    );
  });

  test('固定样例：自定义选集高度与不重复计算离线内边距', () {
    final samples = input['scroll'] as List;
    expect([
      for (final sample in samples)
        if (sample['viewport'] != null)
          calcPageItemOffset(
            index: sample['index'],
            itemCount: sample['count'],
            extent: (sample['extent'] as num).toDouble(),
            viewportDimension: (sample['viewport'] as num).toDouble(),
          )
        else
          (() {
            final r = calcFixedItemOffset(
              index: sample['index'],
              itemCount: sample['count'],
            );
            return [r.$1, r.$2];
          })(),
    ], reference['scroll']);
  });

  test('固定样例：图文大标题和明确字号优先', () {
    expect(
      (input['word'] as List)
          .map((sample) => opus.Word.fromJson(sample).effectiveFontSize)
          .toList(),
      reference['word'],
    );
  });

  test('固定样例：投屏控制地址遵守 URI 根路径和相对路径规则', () {
    expect(
      (input['dlna'] as List).map((sample) {
        final device = DLNADevice(
          DeviceInfo(sample['base'], '', '测试电视', [
            {
              'serviceType': 'urn:schemas-upnp-org:service:AVTransport:1',
              'controlURL': sample['control'],
            },
          ]),
        );
        return device.controlURL('AVTransport');
      }).toList(),
      reference['dlna'],
    );
  });

  for (var i = 0; i < (input['pagination'] as List).length; i++) {
    final sample = input['pagination'][i];
    test('固定样例：${sample['name']}', () async {
      final controller = _Replies(sample['pages']);
      controller.onInit();
      final actual = [];
      for (var n = 0; n < (sample['pages'] as List).length; n++) {
        await controller.queryData(n == 0);
        actual.add({
          'ids': controller.loadingState.value.dataOrNull
              ?.map((r) => r.id.toInt())
              .toList(),
          'offset': controller.nextOffset,
          'end': controller.isEnd,
          'requests': controller.requests,
        });
      }
      // 终止后不得再向接口发送重复请求。
      await controller.onLoadMore();
      expect(controller.requests, (sample['pages'] as List).length);
      expect(actual, reference['pagination'][i]);
      controller.onClose();
    });
  }

  for (var i = 0; i < (input['refresh'] as List).length; i++) {
    final sample = input['refresh'][i];
    testWidgets('固定样例：${sample['name']}', (tester) async {
      var refreshing = RxBool(sample['initial']);
      Widget build() => MaterialApp(
        home: RefreshIndicator_(
          key: const ValueKey('refresh'),
          isRefreshing: refreshing,
        ),
      );
      await tester.pumpWidget(build());
      // 先消耗应用首帧调度，再比较刷新组件的稳定调度状态。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final actual = [
        [
          find.byType(CircularProgressIndicator).evaluate().length,
          tester.binding.hasScheduledFrame,
        ],
      ];
      for (final value in sample['values'] as List) {
        if (value is Map) {
          final previous = refreshing;
          refreshing = RxBool(value['replace']);
          await tester.pumpWidget(build());
          previous.value = !previous.value;
        } else {
          refreshing.value = value;
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        actual.add([
          find.byType(CircularProgressIndicator).evaluate().length,
          tester.binding.hasScheduledFrame,
        ]);
      }
      expect(actual, reference['refresh'][i]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
