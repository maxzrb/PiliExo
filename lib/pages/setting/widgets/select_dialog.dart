import 'dart:async';
import 'dart:convert' show jsonDecode;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

class SelectDialog<T> extends StatelessWidget {
  final T? value;
  final String title;
  final List<(T, String)> values;
  final Widget Function(BuildContext, int)? subtitleBuilder;
  final bool toggleable;
  final List<Widget> leadingItems;

  const SelectDialog({
    super.key,
    this.value,
    required this.values,
    required this.title,
    this.subtitleBuilder,
    this.toggleable = false,
    this.leadingItems = const [],
  });

  @override
  Widget build(BuildContext context) {
    final titleMedium = TextTheme.of(context).titleMedium!;
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: Text(title),
      constraints: subtitleBuilder != null
          ? const BoxConstraints.tightFor(width: 320)
          : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Material(
        type: .transparency,
        child: SingleChildScrollView(
          child: RadioGroup<T>(
            onChanged: (v) => Navigator.of(context).pop(v ?? value),
            groupValue: value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...leadingItems,
                ...List.generate(
                  values.length,
                  (index) {
                    final item = values[index];
                    return RadioListTile<T>(
                      toggleable: toggleable,
                      dense: true,
                      value: item.$1,
                      title: Text(
                        item.$2,
                        style: titleMedium,
                      ),
                      subtitle: subtitleBuilder?.call(context, index),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CdnSelectDialog extends StatefulWidget {
  const CdnSelectDialog({super.key, this.sample});

  final BaseItem? sample;

  @override
  State<CdnSelectDialog> createState() => _CdnSelectDialogState();
}

class _CdnSelectDialogState extends State<CdnSelectDialog> {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'user-agent': BrowserUa.pc,
        'referer': HttpString.baseUrl,
      },
    ),
  );
  final _results = <CDNService, String>{};
  Future<BaseItem>? _sample;
  CancelToken? _presetTest;
  bool _testingPresets = false;

  @override
  void initState() {
    super.initState();
    if (Pref.cdnSpeedTest) unawaited(_testPresets());
  }

  @override
  void dispose() {
    _presetTest?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  Future<BaseItem> _getSample() => _sample ??= () async {
    if (widget.sample case final sample?) return sample;
    final result = await VideoHttp.videoUrl(
      cid: 196018899,
      bvid: 'BV1fK4y1t7hj',
      qn: VideoQuality.high1080.code,
      tryLook: false,
      videoType: VideoType.ugc,
    );
    final item = result.dataOrNull?.dash?.video?.firstOrNull;
    if (item == null) throw StateError('无法获取测速视频流');
    return item;
  }();

  Future<void> _testPresets() async {
    _testingPresets = true;
    final seen = <String, String>{};
    try {
      final sample = await _getSample();
      for (final service in CDNService.values) {
        if (!mounted || !_testingPresets) break;
        final url = VideoUtils.getCdnUrl(
          sample.playUrls,
          defaultCDNService: service,
        );
        final token = _presetTest = CancelToken();
        final result = seen[url] ??= await _measure(url, token);
        if (mounted && _testingPresets) {
          setState(() => _results[service] = result);
        }
      }
    } catch (_) {
      if (mounted && _testingPresets) {
        setState(() {
          for (final service in CDNService.values) {
            _results[service] = '暂无测速样本';
          }
        });
      }
    }
  }

  void _stopPresetTests() {
    _testingPresets = false;
    _presetTest?.cancel();
  }

  Future<String> _measure(String url, CancelToken token) async {
    const limit = 2 * 1024 * 1024;
    final watch = Stopwatch()..start();
    Duration? firstByte;
    var bytes = 0;
    var baseline = 0;
    var deadline = Timer(const Duration(seconds: 8), token.cancel);
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=0-${limit - 1}'},
        ),
        cancelToken: token,
      );
      final body = response.data;
      if (body == null) return '测速失败';
      await for (final chunk in body.stream) {
        if (firstByte == null) {
          firstByte = watch.elapsed;
          baseline = chunk.length;
          deadline.cancel();
          deadline = Timer(const Duration(seconds: 5), token.cancel);
        }
        bytes += chunk.length;
        if (bytes >= limit) break;
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (bytes == 0 && status != null) {
        return 'HTTP $status';
      }
    } finally {
      deadline.cancel();
      token.cancel();
    }
    if (firstByte == null || bytes == 0) return '无测速结果';
    final elapsed = watch.elapsed;
    final hasMore = bytes > baseline;
    final micros = (hasMore ? elapsed - firstByte : elapsed).inMicroseconds;
    if (micros <= 0) return '${firstByte.inMilliseconds} ms';
    final rate = ((hasMore ? bytes - baseline : bytes) / micros)
        .toStringAsPrecision(3);
    return '${firstByte.inMilliseconds} ms · $rate MB/s';
  }

  Future<String> _testNode(String host, CancelToken token) async {
    try {
      final item = await _getSample();
      if (token.isCancelled) return '已取消';
      final url = VideoUtils.getCdnUrl(item.playUrls, customHost: host);
      if (Uri.tryParse(url)?.host != host) return '当前样本不支持此节点';
      return await _measure(url, token);
    } catch (_) {
      return '暂无测速样本';
    }
  }

  void _useHost(String host) {
    Navigator.of(context).pop((service: VideoUtils.cdnService, host: host));
  }

  Future<void> _chooseRegion() async {
    _stopPresetTests();
    final source = await rootBundle.loadString('assets/cdn_nodes.json');
    final nodes = (jsonDecode(source) as Map<String, dynamic>).map(
      (name, hosts) => MapEntry(name, (hosts as List).cast<String>()),
    );
    if (!mounted) return;
    final region = await showDialog<String>(
      context: context,
      builder: (_) => SelectDialog<String>(
        title: '按地区选择 CDN',
        values: nodes.entries
            .map(
              (entry) =>
                  (entry.key, '${entry.key} · ${entry.value.length} 个节点'),
            )
            .toList(),
      ),
    );
    if (!mounted || region == null) return;
    final hosts = nodes[region]!;
    final results = <String, String>{};
    CancelToken? nodeTest;
    try {
      final host = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: Text('$region CDN'),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            content: SizedBox(
              width: 420,
              height: 420,
              child: ListView.builder(
                itemCount: hosts.length,
                itemBuilder: (context, index) {
                  final host = hosts[index];
                  return ListTile(
                    dense: true,
                    title: Text(host),
                    subtitle: results[host] == null
                        ? null
                        : Text(results[host]!),
                    selected: host == VideoUtils.customCdnHost,
                    onTap: () => Navigator.pop(dialogContext, host),
                    trailing: IconButton(
                      tooltip: '测试延迟和速度',
                      icon: const Icon(Icons.speed),
                      onPressed: results[host] == '测速中…'
                          ? null
                          : () async {
                              nodeTest?.cancel();
                              final token = nodeTest = CancelToken();
                              refresh(() => results[host] = '测速中…');
                              final result = await _testNode(host, token);
                              if (dialogContext.mounted) {
                                refresh(() => results[host] = result);
                              }
                            },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (mounted && host != null) _useHost(host);
    } finally {
      nodeTest?.cancel();
    }
  }

  Future<void> _chooseCustom() async {
    _stopPresetTests();
    var input = VideoUtils.customCdnHost ?? '';
    final key = GlobalKey<FormState>();
    final host = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义视频 CDN'),
        content: Form(
          key: key,
          child: TextFormField(
            initialValue: input,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: '域名或 HTTPS 地址'),
            onChanged: (value) => input = value,
            validator: (value) => VideoUtils.normalizeCdnHost(value) == null
                ? '请输入有效的 CDN 域名'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  VideoUtils.normalizeCdnHost(input),
                );
              }
            },
            child: const Text('使用'),
          ),
        ],
      ),
    );
    if (mounted && host != null) _useHost(host);
  }

  @override
  Widget build(BuildContext context) {
    final activeHost = VideoUtils.customCdnHost;
    return SelectDialog<VideoCdnSelection>(
      title: '视频 CDN',
      values: [
        for (final service in CDNService.values)
          ((service: service, host: null), service.desc),
      ],
      value: (service: VideoUtils.cdnService, host: activeHost),
      leadingItems: [
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('按地区选择节点'),
          onTap: _chooseRegion,
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('自定义域名'),
          subtitle: activeHost == null ? null : Text(activeHost),
          selected: activeHost != null,
          onTap: _chooseCustom,
        ),
      ],
      subtitleBuilder: Pref.cdnSpeedTest
          ? (_, index) => Text(_results[CDNService.values[index]] ?? '等待测速')
          : null,
    );
  }
}
