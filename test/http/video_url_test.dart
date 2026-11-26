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
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

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

class _DubPlayer extends Fake implements PlPlayerController {
  @override
  final brightness = 0.0.obs;
  @override
  final int cacheAudioQa = AudioQuality.k192.code;
  @override
  int? cacheVideoQa = 80;
  @override
  final enableSponsorBlock = false;
  @override
  final enableBlock = false;
  @override
  final showViewPoints = false;
  @override
  final showDmChart = false;
  @override
  final tryLook = false;
  @override
  final enableAudioNormalization = false;
  @override
  final processing = false;
  @override
  final playWhenReady = false;
  @override
  final isPlaying = false;
  @override
  Duration currentPosition = const Duration(seconds: 42);

  AudioTrackSwitchResult audioSwitchResult = AudioTrackSwitchResult.unavailable;
  final audioSwitchUrls = <String>[];

  @override
  Future<AudioTrackSwitchResult> switchPlaybackAudioTrack(
    HdrTrackSource track, {
    required bool Function() canApply,
  }) async {
    expect(canApply(), isTrue);
    audioSwitchUrls.add(track.urls.first);
    return audioSwitchResult;
  }
}

class _DubPage extends VideoDetailController {
  _DubPage(_DubPlayer player, PlayUrlModel original)
    : super(playerController: player) {
    bvid = 'BV12gYjzxEix';
    args = {};
    cid = 32230671121.obs;
    videoType = VideoType.ugc;
    isFileSource = false;
    videoState.value = true;
    data = original;
    firstVideo = original.dash!.video!.single;
    languages.value = original.language!.items;
    currLang.value = original.curLanguage;
    currentVideoQa.value = VideoQuality.fromCode(80);
    currentDecodeFormats = VideoDecodeFormatType.AVC;
    currentAudioQa = AudioQuality.k192;
  }

  final loads = <(String?, Duration?, bool?)>[];

  @override
  Future<void>? initPlayerIfNeeded(bool autoFullScreenFlag) => null;

  @override
  Future<void> playerInit({
    bool? autoplay,
    bool autoFullScreenFlag = false,
    Duration? resumePosition,
  }) async {
    loads.add((firstAudio?.baseUrl, resumePosition, autoplay));
  }
}

// 两个语言均用常见音质 ID。切换语言时应根据本次响应选择音频地址。
Map<String, dynamic> _dubResponse(
  String language,
  List<int> audioIds, {
  String? videoUrl,
  bool changesMouth = false,
}) => {
  'cur_language': language,
  'language': {
    'support': true,
    'items': [
      {
        'lang': 'en',
        'title': 'English',
        'production_type': 2,
        'video_mouth_shape_change': changesMouth,
      },
    ],
  },
  'dash': {
    'video': [
      {
        'id': 80,
        'codecs': 'avc1.640034',
        'base_url': videoUrl ?? 'https://example.com/video/$language.m4s',
      },
    ],
    'audio': [
      for (final id in audioIds)
        {
          'id': id,
          'base_url': 'https://example.com/audio/$language-$id.m4s',
        },
    ],
  },
};

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

  // 固定样例仅验证真实播放函数的拒绝响应处理，不代表平台实播验收。
  final accessInput = jsonDecode(
    File('test/fixtures/playback_access_boundary/input.json')
        .readAsStringSync(encoding: utf8),
  ) as List;
  final accessReference = jsonDecode(
    File('test/fixtures/playback_access_boundary/reference.json')
        .readAsStringSync(encoding: utf8),
  ) as List;
  for (var i = 0; i < accessInput.length; i++) {
    final sample = accessInput[i];
    test('播放权限固定样例：${sample['name']}', () async {
      adapter.responses.addAll(
        (sample['responses'] as List).cast<Map<String, dynamic>>(),
      );
      final result = await VideoHttp.videoUrl(
        cid: 123,
        qn: 80,
        tryLook: sample['tryLook'] as bool,
        videoType: VideoType.values.byName(sample['type']),
      );
      final data = result.dataOrNull;
      expect({
        'name': sample['name'],
        'requests': adapter.requests.length,
        'tryLookSent': adapter.requests.single.queryParameters['try_look'] == 1,
        'isError': result is Error,
        'mentionsCharge':
            result is Error && (result.errMsg?.contains('充电') ?? false),
        'hasPlayModel': data != null,
        'videoStreams': data?.dash?.video?.length ?? 0,
        'segments': data?.durl?.length ?? 0,
      }, accessReference[i]);
      expect(adapter.responses, isEmpty);
    });
  }

  group('配音语言', () {
    setUp(() {
      Accounts.accountMode[AccountType.video.index] = LoginAccount(
        BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'csrf'}),
        'access-key',
        'refresh-token',
      );
    });

    test('首次进入和切换分 P 都请求原声', () async {
      final original = _dubResponse('', [30280])..remove('cur_language');
      final dubbed = _dubResponse('en', [30232]);
      final page = _DubPage(_DubPlayer(), PlayUrlModel.fromJson(original));
      adapter.responses.addAll([
        {'code': 0, 'data': original},
        {'code': 0, 'data': dubbed},
        {'code': 0, 'data': original},
      ]);

      await page.queryVideoUrl();
      await page.setLanguage('en');
      expect(page.currLang.value, 'en');
      page.onReset();
      page.cid.value += 1;
      await page.queryVideoUrl();

      expect(page.currLang.value ?? '', '');
      expect(page.firstAudio?.baseUrl, 'https://example.com/audio/-30280.m4s');
      expect(
        adapter.requests.map(
          (request) => request.queryParameters['cur_language'],
        ),
        ['', 'en', ''],
      );
    });

    test('切换配音保留暂停、进度和首选音质，恢复原声时重新应用首选档', () async {
      final player = _DubPlayer();
      final original = _dubResponse('', [30232, 30280]);
      final page = _DubPage(player, PlayUrlModel.fromJson(original));
      adapter.responses.addAll([
        {
          'code': 0,
          'data': _dubResponse('en', [30232]),
        },
        {'code': 0, 'data': original},
      ]);
      expect(page.audioLanguageOptions.map((item) => item.title), [
        '原声',
        'English（AI）',
      ]);

      await page.setLanguage('en');
      expect(page.currLang.value, 'en');
      expect(page.currentAudioQa, AudioQuality.k132);
      expect(player.cacheAudioQa, AudioQuality.k192.code);
      expect(page.loads.single, (
        'https://example.com/audio/en-30232.m4s',
        const Duration(seconds: 42),
        false,
      ));

      player.currentPosition = const Duration(seconds: 57);
      await page.setLanguage('');
      expect(page.currLang.value, '');
      expect(page.currentAudioQa, AudioQuality.k192);
      expect(page.loads.last, (
        'https://example.com/audio/-30280.m4s',
        const Duration(seconds: 57),
        false,
      ));
      expect(
        adapter.requests.map(
          (request) => request.queryParameters['cur_language'],
        ),
        ['en', ''],
      );
      expect(player.audioSwitchUrls, isEmpty);
    });

    const videoPath = '/upgcxcode/21/11/32230671121/32230671121-1-30080.m4s';
    final sameVideoOriginal = _dubResponse(
      '',
      [30280],
      videoUrl: 'https://a.bilivideo.com$videoPath?deadline=1',
    );
    final sameVideoDubbed = _dubResponse(
      'en',
      [30232],
      videoUrl: 'https://b.bilivideo.com$videoPath?deadline=2',
    );

    test('相同视频分轨换 CDN 时原地切换配音和原声', () async {
      final player = _DubPlayer()
        ..audioSwitchResult = AudioTrackSwitchResult.switched;
      final page = _DubPage(player, PlayUrlModel.fromJson(sameVideoOriginal));
      adapter.responses.addAll([
        {'code': 0, 'data': sameVideoDubbed},
        {'code': 0, 'data': sameVideoOriginal},
      ]);

      await page.setLanguage('en');
      expect(page.currLang.value, 'en');
      await page.setLanguage('');
      expect(page.currLang.value, '');
      expect(player.audioSwitchUrls, [
        'https://example.com/audio/en-30232.m4s',
        'https://example.com/audio/-30280.m4s',
      ]);
      expect(page.loads, isEmpty);
    });

    test('配音包含口型改动时重新加载声画并恢复进度', () async {
      final player = _DubPlayer()
        ..audioSwitchResult = AudioTrackSwitchResult.switched;
      final page = _DubPage(player, PlayUrlModel.fromJson(sameVideoOriginal));
      adapter.responses.add({
        'code': 0,
        'data': _dubResponse(
          'en',
          [30232],
          videoUrl: 'https://b.bilivideo.com$videoPath?deadline=2',
          changesMouth: true,
        ),
      });

      await page.setLanguage('en');
      expect(player.audioSwitchUrls, isEmpty);
      expect(page.loads.single.$2, const Duration(seconds: 42));
    });

    testWidgets('原地切轨失败时保留原声且不重载', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const SizedBox.shrink(),
        ),
      );
      final player = _DubPlayer()
        ..audioSwitchResult = AudioTrackSwitchResult.failed;
      final original = PlayUrlModel.fromJson(sameVideoOriginal);
      final page = _DubPage(player, original);
      adapter.responses.add({'code': 0, 'data': sameVideoDubbed});

      await tester.runAsync(() => page.setLanguage('en'));

      expect(page.data, same(original));
      expect(page.currLang.value, '');
      expect(page.loads, isEmpty);
      expect(page.switchingAudioLanguage.value, isFalse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('接口返回原声时不切换或重载当前播放', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: FlutterSmartDialog.init(),
          home: const SizedBox.shrink(),
        ),
      );
      final original = _dubResponse('', [30232, 30280]);
      final page = _DubPage(_DubPlayer(), PlayUrlModel.fromJson(original));
      adapter.responses.add({'code': 0, 'data': original});

      await tester.runAsync(() => page.setLanguage('en'));

      expect(adapter.requests.single.queryParameters['cur_language'], 'en');
      expect(page.currLang.value, '');
      expect(page.currentAudioQa, AudioQuality.k192);
      expect(page.loads, isEmpty);
      expect(page.videoState.value, isTrue);
      expect(page.switchingAudioLanguage.value, isFalse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

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
