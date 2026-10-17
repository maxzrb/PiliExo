import 'dart:async';

/// 将用户基础倍速与长按临时倍速分开，并只保留尚未执行的最新请求。
class PlaybackRateCoordinator {
  PlaybackRateCoordinator({
    required double initialRate,
    required this.apply,
    required this.onConfirmed,
  }) : _baseRate = initialRate;

  // 后端取得自身操作锁后再次检查，避免等待seek期间已松手的旧请求仍被执行。
  final Future<void> Function(double rate, bool Function() isCurrent) apply;
  final void Function(double rate) onConfirmed;
  double _baseRate;
  double? _temporaryRate;
  double? _confirmedRate;
  double? _pendingRate;
  int _revision = 0;
  int _generation = 0;
  bool _disposed = false;
  Completer<void>? _completion;

  double get baseRate => _baseRate;
  double? get temporaryRate => _temporaryRate;
  double? get confirmedRate => _confirmedRate;
  double get targetRate => _temporaryRate ?? _baseRate;
  bool get isTemporary => _temporaryRate != null;

  Future<void> setBaseRate(double rate) {
    _validate(rate);
    _baseRate = rate;
    _temporaryRate = null;
    return _request(rate);
  }

  Future<void> beginTemporary(double rate) {
    _validate(rate);
    if (_temporaryRate == rate) {
      return _completion?.future ?? Future<void>.value();
    }
    _temporaryRate = rate;
    return _request(rate);
  }

  Future<void> endTemporary() {
    _temporaryRate = null;
    return _request(_baseRate);
  }

  /// 切源后不沿用旧后端的确认结果；已经发出的原生命令不能撤销。
  void resetForSource() {
    _generation++;
    _revision++;
    _temporaryRate = null;
    _confirmedRate = null;
    _pendingRate = null;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  void dispose() {
    resetForSource();
    _disposed = true;
  }

  void _validate(double rate) {
    if (_disposed) throw StateError('倍速协调器已经释放');
    if (!rate.isFinite || rate <= 0) {
      throw ArgumentError.value(rate, 'rate', '倍速必须为有限正数');
    }
  }

  Future<void> _request(double rate) {
    _validate(rate);
    if (_completion == null && _confirmedRate == rate) {
      return Future<void>.value();
    }
    _revision++;
    _pendingRate = rate;
    final running = _completion;
    if (running != null) return running.future;
    final completion = _completion = Completer<void>();
    unawaited(_drain(completion, _generation));
    return completion.future;
  }

  Future<void> _drain(Completer<void> completion, int generation) async {
    try {
      while (!_disposed && generation == _generation && _pendingRate != null) {
        final rate = _pendingRate!;
        _pendingRate = null;
        final revision = _revision;
        try {
          await apply(
            rate,
            () =>
                !_disposed &&
                generation == _generation &&
                revision == _revision,
          );
        } catch (_) {
          // 过时请求失败仍须执行最终恢复目标，不能让队列卡死。
          if (generation == _generation && revision == _revision) rethrow;
          continue;
        }
        if (!_disposed && generation == _generation && revision == _revision) {
          _confirmedRate = rate;
          onConfirmed(rate);
        }
      }
      if (identical(_completion, completion)) _completion = null;
      if (!completion.isCompleted) completion.complete();
    } catch (error, stack) {
      if (identical(_completion, completion)) {
        _completion = null;
        _confirmedRate = null;
      }
      if (!completion.isCompleted) completion.completeError(error, stack);
    }
  }
}
