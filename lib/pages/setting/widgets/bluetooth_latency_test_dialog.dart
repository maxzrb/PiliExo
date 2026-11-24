import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/models/bluetooth_latency.dart';
import 'package:PiliPlus/plugin/pl_player/utils/bluetooth_latency_service.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

class BluetoothLatencyTestDialog extends StatefulWidget {
  const BluetoothLatencyTestDialog({
    super.key,
    required this.initialTrimMs,
  });

  final int initialTrimMs;

  @override
  State<BluetoothLatencyTestDialog> createState() =>
      _BluetoothLatencyTestDialogState();
}

class _BluetoothLatencyTestDialogState extends State<BluetoothLatencyTestDialog>
    with SingleTickerProviderStateMixin {
  static const _flashUs = 260000;
  static const _trimStepMs = 5;

  final _service = BluetoothLatencyService.instance;
  late final _ticker = createTicker(_onTick);
  late final AppLifecycleListener _lifecycle;
  late final BluetoothAudioCodec _codec;
  StreamSubscription<int>? _calibration;
  late int _trimMs;
  bool _audioFailed = false;
  int? _cueUs;
  int? _flashOffUs;

  // 以声音为参考，正值晚闪，负值早闪，与播放器的相对音画偏移一致。
  int get _previewDelayMs => -BluetoothLatencyPolicy.computeDelayMs(
    enabled: true,
    info: _service.info.value,
    codec: _codec,
    trimMs: _trimMs,
  );

  @override
  void initState() {
    super.initState();
    _codec = _service.codec;
    _lifecycle = AppLifecycleListener(onHide: _stop);
    _service.info.addListener(_onOutputChanged);
    _trimMs = widget.initialTrimMs.clamp(
      BluetoothLatencyPolicy.minTrimMs,
      BluetoothLatencyPolicy.maxTrimMs,
    );
  }

  void _onOutputChanged() {
    if (!_service.hasBluetoothOutput && _calibration != null) {
      _stop();
    } else {
      setState(() {});
    }
  }

  void _start() {
    setState(() {
      _audioFailed = false;
      _calibration = _service.calibrationCues().listen(
        (cueUs) {
          _cueUs = cueUs;
          if (!_ticker.isActive) _ticker.start();
        },
        onError: (Object _) => _stop(failed: true),
        onDone: () => _stop(failed: true),
      );
    });
  }

  void _stop({bool failed = false}) {
    if (_calibration == null) return;
    unawaited(_calibration?.cancel());
    _ticker.stop();
    setState(() {
      _calibration = null;
      _cueUs = null;
      _flashOffUs = null;
      _audioFailed = failed;
    });
  }

  void _setTrim(int ms) {
    setState(() {
      _trimMs = ms.clamp(
        BluetoothLatencyPolicy.minTrimMs,
        BluetoothLatencyPolicy.maxTrimMs,
      );
    });
  }

  void _onTick(Duration _) {
    // Android 的 Flutter 帧时间和原生音频节拍使用同一个单调时钟。
    final nowUs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    if (_flashOffUs case final offUs?) {
      if (nowUs < offUs) return;
      setState(() => _flashOffUs = null);
    }
    if (_cueUs case final cueUs?) {
      final flashUs = cueUs + _previewDelayMs * 1000;
      if (nowUs < flashUs) return;
      _cueUs = null;
      if (nowUs - flashUs < _flashUs) {
        setState(() => _flashOffUs = nowUs + _flashUs);
        debugPrint(
          'BluetoothLatencyFlash: on cueUs=$cueUs '
          'targetUs=$flashUs frameUs=$nowUs',
        );
        return;
      }
    }
    _ticker.stop();
  }

  @override
  void dispose() {
    _service.info.removeListener(_onOutputChanged);
    _lifecycle.dispose();
    unawaited(_calibration?.cancel());
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final flash = _flashOffUs != null;
    final delay = _previewDelayMs;
    final trimLabel = BluetoothLatencyPolicy.formatSignedMs(_trimMs);
    return AlertDialog(
      title: const Text('额外补偿'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('bluetooth-calibration-flash'),
              height: 126,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: flash
                      ? colorScheme.onPrimary
                      : colorScheme.outlineVariant,
                  width: flash ? 4 : 1,
                ),
                color: flash
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                flash ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                size: 58,
                color: flash
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '每 3 秒闪动并响一声。根据听到声音与看到闪动的先后顺序微调，直到两者对齐。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${_service.statusText} · 总补偿 '
              '${BluetoothLatencyPolicy.formatSignedMs(delay)}',
              style: theme.textTheme.bodySmall,
            ),
            if (_audioFailed)
              Text(
                '校准音频播放失败，请重试。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            Slider(
              value: _trimMs.toDouble(),
              min: BluetoothLatencyPolicy.minTrimMs.toDouble(),
              max: BluetoothLatencyPolicy.maxTrimMs.toDouble(),
              divisions:
                  (BluetoothLatencyPolicy.maxTrimMs -
                      BluetoothLatencyPolicy.minTrimMs) ~/
                  _trimStepMs,
              label: trimLabel,
              onChanged: (value) => _setTrim(value.round()),
            ),
            DefaultTextStyle(
              style: theme.textTheme.labelSmall!.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('声音先到'),
                  Text(
                    trimLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Text('声音后到'),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _service.hasBluetoothOutput
              ? (_calibration == null ? _start : _stop)
              : null,
          child: Text(_calibration == null ? '开始校准' : '停止'),
        ),
        TextButton(
          onPressed: () {
            _stop();
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            _stop();
            Navigator.pop(context, _trimMs);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
