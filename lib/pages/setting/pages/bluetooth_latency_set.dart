import 'dart:async';

import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/widgets/bluetooth_latency_test_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/normal_item.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/switch_item.dart';
import 'package:PiliPlus/plugin/pl_player/models/bluetooth_latency.dart';
import 'package:PiliPlus/plugin/pl_player/utils/bluetooth_latency_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

class BluetoothLatencySettingPage extends StatefulWidget {
  const BluetoothLatencySettingPage({super.key});

  @override
  State<BluetoothLatencySettingPage> createState() =>
      _BluetoothLatencySettingPageState();
}

class _BluetoothLatencySettingPageState
    extends State<BluetoothLatencySettingPage> {
  final _service = BluetoothLatencyService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_service.refreshAndApply());
  }

  Future<void> _showCodecDialog(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    final res = await showDialog<BluetoothAudioCodec>(
      context: context,
      builder: (context) => SelectDialog<BluetoothAudioCodec>(
        title: '蓝牙音频编码',
        value: BluetoothAudioCodec.fromName(Pref.bluetoothLatencyCodec),
        values: BluetoothAudioCodec.values
            .map((codec) => (codec, codec.desc))
            .toList(),
      ),
    );
    if (res == null) return;
    await GStorage.setting.put(
      SettingBoxKey.bluetoothLatencyCodec,
      res.name,
    );
    await _service.refreshAndApply();
    refresh();
  }

  Future<void> _showExtraCompensationDialog(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    await _service.refreshAndApply();
    if (!context.mounted || !_service.isCompensationActive) return;
    final res = await showDialog<int>(
      context: context,
      builder: (context) => BluetoothLatencyTestDialog(
        initialTrimMs: Pref.bluetoothLatencyTrimMs,
      ),
    );
    if (res == null) return;
    await GStorage.setting.put(
      SettingBoxKey.bluetoothLatencyTrimMs,
      res,
    );
    await _service.refreshAndApply();
    refresh();
  }

  @override
  Widget build(BuildContext context) => SimpleScaffold(
    appBar: AppBar(title: const Text('蓝牙延迟补偿')),
    body: ValueListenableBuilder(
      valueListenable: _service.info,
      builder: (context, _, _) => _buildSettings(context),
    ),
  );

  Widget _buildSettings(BuildContext context) {
    final theme = Theme.of(context);
    final available = _service.hasBluetoothOutput;
    final enabled = _service.isCompensationActive;
    final preference = Pref.bluetoothLatencyCompensation;
    return ListView(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text(
            '连接蓝牙耳机后，可按协议估算延迟，并用“额外补偿”按实际听感校准。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SetSwitchItem(
          title: '蓝牙延迟补偿',
          subtitle: available
              ? '让画面与蓝牙耳机返回的声音保持对齐'
              : preference
              ? '连接蓝牙音频设备后恢复补偿'
              : '连接蓝牙音频设备后可开启',
          leading: const Icon(Icons.bluetooth_rounded),
          setKey: SettingBoxKey.bluetoothLatencyCompensation,
          enabled: available,
          onChanged: (_) async {
            await _service.refreshAndApply();
            if (mounted) setState(() {});
          },
        ),
        if (enabled) ...[
          NormalItem(
            title: '蓝牙输出状态',
            getSubtitle: () => '${_service.summaryText}；点击刷新',
            leading: const Icon(Icons.headphones_outlined),
            getTrailing: (_) => const Icon(Icons.refresh_rounded),
            onTap: (context, refresh) async {
              await _service.refreshAndApply();
              refresh();
            },
          ),
          NormalItem(
            title: '蓝牙音频编码',
            getSubtitle: () {
              final codec = BluetoothAudioCodec.fromName(
                Pref.bluetoothLatencyCodec,
              );
              return '当前：${codec.desc}；自动按协议估算，手动编码主要用于 A2DP';
            },
            leading: const Icon(Icons.graphic_eq_rounded),
            getTrailing: (_) => const Icon(Icons.chevron_right_rounded),
            onTap: _showCodecDialog,
          ),
          NormalItem(
            title: '额外补偿',
            getSubtitle: () {
              final trim = Pref.bluetoothLatencyTrimMs;
              return '${BluetoothLatencyPolicy.formatSignedMs(trim)}；打开柔和提示音与闪动校准';
            },
            leading: const Icon(Icons.tune_rounded),
            getTrailing: (_) => const Icon(Icons.chevron_right_rounded),
            onTap: _showExtraCompensationDialog,
          ),
        ],
      ],
    );
  }
}
