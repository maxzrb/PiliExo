import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cosov =
      'https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/01/video.m4s'
      '?os=cosovbv&upsig=cosov-signature';
  const akamai =
      'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/01/video.m4s'
      '?os=akam&upsig=akamai-signature&hdnts=exp%3D123~hmac%3Dabc&x=one%2btwo';
  const mcdn = 'https://example.mcdn.bilivideo.cn:4483/v1/resource/video.m4s';

  setUp(() {
    VideoUtils.cdnService = CDNService.akamai;
    VideoUtils.customCdnHost = null;
    VideoUtils.disableAudioCDN = false;
  });

  test('Akamai selects its signed backup without changing any bytes', () {
    expect(VideoUtils.getCdnUrl([cosov, akamai]), akamai);
  });

  test('Akamai keeps a signed primary URL', () {
    expect(VideoUtils.getCdnUrl([akamai, cosov]), akamai);
  });

  test('Akamai finds its backup after a relay URL', () {
    expect(VideoUtils.getCdnUrl([mcdn, cosov, akamai]), akamai);
  });

  test('missing Akamai backup preserves the original primary URL', () {
    expect(VideoUtils.getCdnUrl([cosov]), cosov);
    expect(VideoUtils.getCdnUrl([mcdn, cosov]), mcdn);
  });

  test('Akamai selects the signed audio backup too', () {
    expect(VideoUtils.getCdnUrl([cosov, akamai], isAudio: true), akamai);
  });

  test('disabled audio CDN still keeps the original audio mirror', () {
    VideoUtils.disableAudioCDN = true;
    expect(VideoUtils.getCdnUrl([cosov, akamai], isAudio: true), cosov);
    expect(VideoUtils.getCdnUrl([cosov, akamai]), akamai);
  });

  test('base and backup selection retain their existing behavior', () {
    expect(
      VideoUtils.getCdnUrl([
        mcdn,
        cosov,
        akamai,
      ], defaultCDNService: CDNService.baseUrl),
      mcdn,
    );
    expect(
      VideoUtils.getCdnUrl([
        mcdn,
        cosov,
        akamai,
      ], defaultCDNService: CDNService.backupUrl),
      cosov,
    );
  });

  test('other configured mirrors retain their existing behavior', () {
    expect(
      VideoUtils.getCdnUrl([cosov, akamai], defaultCDNService: CDNService.ali),
      Uri.parse(cosov).replace(host: CDNService.ali.host).toString(),
    );
  });

  test('Akamai hostname must match exactly', () {
    const lookalike =
        'https://upos-hz-mirrorakam.akamaized.net.example.com/video.m4s';
    expect(VideoUtils.getCdnUrl([cosov, lookalike, akamai]), akamai);
    expect(VideoUtils.getCdnUrl([cosov, lookalike]), cosov);
  });

  test(
    'normalizes CDN domains without keeping query strings or credentials',
    () {
      expect(
        VideoUtils.normalizeCdnHost(
          ' https://CN-SH-CT-01-01.bilivideo.com/upgcxcode/1?x=2 ',
        ),
        'cn-sh-ct-01-01.bilivideo.com',
      );
      expect(VideoUtils.normalizeCdnHost('cdn.example.com/extra'), isNull);
      expect(
        VideoUtils.normalizeCdnHost('https://user@cdn.example.com'),
        isNull,
      );
      expect(VideoUtils.normalizeCdnHost('ftp://cdn.example.com'), isNull);
    },
  );

  test('selects the exact signed URL for a configured regional host', () {
    const host = 'cn-sh-ct-01-01.bilivideo.com';
    const signed =
        'https://$host/upgcxcode/01/video.m4s?upsig=regional-signature&x=one%2btwo';
    VideoUtils.customCdnHost = host;
    expect(VideoUtils.getCdnUrl([cosov, signed, akamai]), signed);
  });

  test('uses the regional host with the original mirror URL as a fallback', () {
    const host = 'cn-sh-ct-01-01.bilivideo.com';
    VideoUtils.customCdnHost = host;
    final routes = VideoUtils.getCdnUrls([cosov, akamai]);
    expect(routes.first, Uri.parse(cosov).replace(host: host).toString());
    expect(routes, containsAll([cosov, akamai]));
    expect(
      VideoUtils.getCdnUrl([
        cosov,
        akamai,
      ], defaultCDNService: CDNService.akamai),
      akamai,
    );
  });

  test('custom hosts do not affect audio with CDN replacement disabled', () {
    VideoUtils.customCdnHost = 'cn-sh-ct-01-01.bilivideo.com';
    VideoUtils.disableAudioCDN = true;
    expect(VideoUtils.getCdnUrl([cosov, akamai], isAudio: true), cosov);
  });

  test(
    'custom hosts are not used to rewrite Akamai-only media or API URLs',
    () {
      VideoUtils.cdnService = CDNService.baseUrl;
      VideoUtils.customCdnHost = 'cn-sh-ct-01-01.bilivideo.com';
      const api = 'https://bvc.bilivideo.com/pbp/data';
      expect(VideoUtils.getCdnUrl([akamai]), akamai);
      expect(VideoUtils.getCdnUrl([api]), api);
    },
  );
}
