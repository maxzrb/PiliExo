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
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _PlayUrlAdapter implements HttpClientAdapter {
  final responses = <Map<String, dynamic>>[];
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (responses.isEmpty) throw StateError('固定响应已用完，禁止额外请求');
    return ResponseBody.fromString(
      jsonEncode(responses.removeAt(0)),
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
    // 使用临时存储，所有请求由内存适配器响应。
    directory = await Directory.systemTemp.createTemp('ogv-test-');
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
    adapter.responses.clear();
    adapter.requests.clear();
    Accounts.accountMode[AccountType.video.index] = AnonymousAccount();
  });

  tearDownAll(() async {
    Request.dio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  final input = jsonDecode(
    File('test/fixtures/upstream_20261104/input.json')
        .readAsStringSync(encoding: utf8),
  );
  final reference = jsonDecode(
    File('test/fixtures/upstream_20261104/reference.json')
        .readAsStringSync(encoding: utf8),
  );
  for (var i = 0; i < (input['video'] as List).length; i++) {
    final sample = input['video'][i];
    test('固定样例：${sample['name']}', () async {
      adapter.responses.addAll(
        (sample['responses'] as List).cast<Map<String, dynamic>>(),
      );
      final result = await VideoHttp.videoUrl(
        cid: 123,
        qn: 129,
        epid: 456,
        seasonId: 789,
        tryLook: false,
        videoType: VideoType.values.byName(sample['type']),
        language: 'zh-Hans',
        voiceBalance: true,
      );
      expect({
        'requests': adapter.requests
            .map(
              (request) => {
                'path': request.path,
                'method': request.method,
                'bizType': request.queryParameters['biz_type'],
                'epid': request.queryParameters['ep_id'],
                'qn': request.queryParameters['qn'],
                'language': request.queryParameters['cur_language'],
                'voiceBalance': request.queryParameters['voice_balance'],
                'hasBody': request.data != null,
                'fnval': request.queryParameters['fnval'],
              },
            )
            .toList(),
        'quality': result.dataOrNull?.quality,
        'progress': result.dataOrNull?.lastPlayTime,
        'error': result is Error ? result.errMsg : null,
      }, reference['video'][i]);
      expect(adapter.responses, isEmpty);
    });
  }

  test('匿名网页 Cookie 获取成功或失败均保留 APP/gRPC 独立标识', () async {
    final anonymous = AnonymousAccount();
    final originalBuvid = anonymous.buvid;
    final originalHeaders = Map<String, String>.from(anonymous.grpcHeaders);
    adapter.responses.add({
      'code': 0,
      'data': {'b_3': 'web-b3', 'b_4': 'web-b4'},
    });
    await anonymous.refreshWebCookies();
    expect(anonymous.cookieJar.toJson(), containsPair('buvid3', 'web-b3'));
    expect(anonymous.cookieJar.toJson(), containsPair('buvid4', 'web-b4'));
    expect(adapter.requests.single.extra['account'], isA<NoAccount>());
    for (final response in [
      {'code': -1, 'message': '固定失败'},
      {
        'code': 0,
        'data': {'b_3': '', 'b_4': 'bad'},
      },
    ]) {
      adapter.responses.add(response);
      await anonymous.refreshWebCookies();
      expect(anonymous.cookieJar.toJson(), containsPair('buvid3', 'web-b3'));
    }
    expect(anonymous.buvid, originalBuvid);
    expect(anonymous.grpcHeaders, originalHeaders);
    expect(Pref.buvid, originalBuvid);
  });

  test('匿名与视频账号的 buvid 独立且各自同步 gRPC 元数据', () async {
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
    expect(account.grpcHeaders['buvid'], oldBuvid);
    account.buvid = 'XY-VIDEO-DEVICE-ID';
    await account.onChange();
    for (final current in {account, AnonymousAccount()}) {
      final expected = current == account
          ? 'XY-VIDEO-DEVICE-ID'
          : 'XY-NEW-DEVICE-ID';
      final headers = current.grpcHeaders;
      expect(headers['buvid'], expected);
      expect(
        Device.fromBuffer(base64Decode(headers['x-bili-device-bin']!)).buvid,
        expected,
      );
      expect(
        Metadata.fromBuffer(base64Decode(headers['x-bili-metadata-bin']!))
            .buvid,
        expected,
      );
    }
    expect(GStorage.setting.get(SettingBoxKey.buvid), 'XY-NEW-DEVICE-ID');
  });
}
