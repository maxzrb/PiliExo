import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/grpc/bilibili/metadata/device.pb.dart';
import 'package:PiliPlus/grpc/bilibili/metadata.pb.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _PlayUrlAdapter implements HttpClientAdapter {
  Map<String, dynamic> response = {};
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final adapter = _PlayUrlAdapter();

  setUpAll(() async {
    // 使用项目内的临时存储，所有请求由内存适配器响应。
    directory = await Directory('tools').createTemp('ogv-test-');
    Hive.init(directory.path);
    GStorage.regAdapter();
    Accounts.account = await Hive.openBox<LoginAccount>('account');
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    await GStorage.setting.put(SettingBoxKey.enableHttp2, false);
    await GStorage.setting.put(SettingBoxKey.retryCount, 0);
    await GStorage.localCache.putAll({
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: '0123456789abcdef0123456789abcdef',
    });
    Request();
    Request.dio.httpClientAdapter = adapter;
  });

  setUp(() {
    Accounts.accountMode[AccountType.video.index] = AnonymousAccount();
  });

  tearDownAll(() async {
    Request.dio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<LoadingState<dynamic>> load(VideoType type) => VideoHttp.videoUrl(
    cid: 123,
    qn: 120,
    epid: 456,
    seasonId: 789,
    tryLook: false,
    videoType: type,
  );

  test('番剧使用 POST 和 JSON 参数，恢复新接口的续播进度', () async {
    adapter.response = {
      'code': 0,
      'data': {
        'video_info': {'quality': 120},
        'watch_progress': {'current_watch_progress': 12000},
      },
    };
    final result = await load(.pgc);
    expect(adapter.request.method, 'POST');
    expect(adapter.request.path, '/ogv/player/playview');
    expect(adapter.request.data['video_index']['ogv_episode_id'], 456);
    expect(adapter.request.data['video_param']['qn'], 120);
    expect(
      jsonDecode(adapter.request.queryParameters['x-bili-device-req-json']),
      containsPair('platform', 'web'),
    );
    expect(adapter.request.queryParameters.containsKey('csrf'), isFalse);
    expect(result.dataOrNull?.quality, 120);
    expect(result.dataOrNull?.lastPlayTime, 12000);
  });

  test('课程保留 GET，兼容另一种续播字段', () async {
    adapter.response = {
      'code': 0,
      'data': {
        'video_info': {'quality': 80},
        'watch_progress': {'current_progress': 9000},
      },
    };
    final result = await load(.pugv);
    expect(adapter.request.method, 'GET');
    expect(adapter.request.queryParameters['biz_type'], 'pugv');
    expect(adapter.request.data, isNull);
    expect(result.dataOrNull?.lastPlayTime, 9000);
  });

  test('登录时番剧请求携带视频账户 csrf', () async {
    Accounts.accountMode[AccountType.video.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'video-csrf'}),
      'access-key',
      'refresh-token',
    );
    adapter.response = {
      'code': 0,
      'data': {'video_info': <String, dynamic>{}},
    };
    await load(.pgc);
    expect(adapter.request.queryParameters['csrf'], 'video-csrf');
  });

  test('无播放权限和缺失播放信息均返回业务错误', () async {
    adapter.response = {
      'code': 0,
      'data': {
        'not_playable_reason': {'code': -404, 'message': '不可播放'},
      },
    };
    expect(await load(.pgc), isA<Error>());
    adapter.response = {'code': 0, 'data': <String, dynamic>{}};
    final result = await load(.pgc);
    expect(result, isA<Error>());
    expect((result as Error).errMsg, '未获取到播放信息');
  });

  test('修改 buvid 同步登录头及已有账户的 gRPC 元数据', () async {
    final account = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'csrf'}),
      'access-key',
      'refresh-token',
    );
    Accounts.accountMode[AccountType.video.index] = account;
    final oldBuvid = account.grpcHeaders['buvid'];
    await LoginUtils.setBuvid('XY-NEW-DEVICE-ID');
    expect(oldBuvid, isNot('XY-NEW-DEVICE-ID'));
    expect(LoginHttp.headers['buvid'], 'XY-NEW-DEVICE-ID');
    for (final current in {account, AnonymousAccount()}) {
      final headers = current.grpcHeaders;
      expect(headers['buvid'], 'XY-NEW-DEVICE-ID');
      expect(
        Device.fromBuffer(base64Decode(headers['x-bili-device-bin']!)).buvid,
        'XY-NEW-DEVICE-ID',
      );
      expect(
        Metadata.fromBuffer(base64Decode(headers['x-bili-metadata-bin']!))
            .buvid,
        'XY-NEW-DEVICE-ID',
      );
    }
    expect(GStorage.setting.get(SettingBoxKey.buvid), 'XY-NEW-DEVICE-ID');
  });
}
