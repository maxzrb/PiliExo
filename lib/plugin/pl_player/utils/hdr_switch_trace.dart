import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/utils/mpv_runtime_observer.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

abstract final class HdrSwitchTrace {
  static const enabled = bool.fromEnvironment('PILIEXO_HDR_SWITCH_TRACE');
  static const fileName = 'piliexo-hdr-switch-trace.jsonl';

  static final _clock = Stopwatch()..start();
  static Future<File?>? _file;
  static Future<void> _pendingWrite = Future<void>.value();
  static int _sequence = 0;
  static int _lines = 0;

  static int nextId() => ++_sequence;

  static Future<File?> _open() async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) return null;
    final file = File('${directory.path}/$fileName');
    if (await file.exists() && await file.length() > 512 * 1024) {
      await file.writeAsString('');
    }
    return file;
  }

  static void record(String event, [Map<String, Object?> data = const {}]) {
    if (!enabled || !Platform.isAndroid || _lines >= 1500) return;
    _lines++;
    final line = jsonEncode({
      'ms': _clock.elapsedMilliseconds,
      'event': event,
      ...data,
    });
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final file = await (_file ??= _open());
        await file?.writeAsString('$line\n', mode: FileMode.append);
      } on Exception {
        debugPrint('PiliExo HDR trace: file write failed');
      }
    });
  }

  static Timer sample(
    MpvRuntimeObserver observer, {
    required int source,
    required int operation,
    required Map<String, Object?> Function() appState,
  }) {
    return Timer.periodic(const Duration(milliseconds: 500), (timer) {
      observer.poll();
      record('mpv.sample', {
        'source': source,
        'operation': operation,
        ...observer.traceProperties,
        ...appState(),
      });
      if (timer.tick == 24) timer.cancel();
    });
  }
}
