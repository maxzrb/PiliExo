import 'dart:async';

/// 将用户基础倍速与长按临时倍速分开，并只保留尚未执行的最新请求。
class PlaybackRateCoordinator {
  PlaybackRateCoordinator({
    required double initialRate,
    required this.apply,
    required this.onConfirmed,
  }) : _baseRate = initialRate;

  // 后端发送前再次检查有效性；不得持有操作锁等待旧命令回复后才发送恢复。
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
  int _inFlight = 0;
  bool _dispatchScheduled = false;

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
    final completion = _completion ??= Completer<void>();
    if (_inFlight == 0) {
      unawaited(_dispatchLatest());
    } else if (!_dispatchScheduled) {
      // 同一事件循环只发送最新目标，但不等待已经发出的加速命令确认。
      // 松手的恢复必须及时进入原生命令队列，不能被迟到回复阻挡。
      _dispatchScheduled = true;
      scheduleMicrotask(() {
        _dispatchScheduled = false;
        if (!_disposed && _pendingRate != null) {
          unawaited(_dispatchLatest());
        }
      });
    }
    return completion.future;
  }

  Future<void> _dispatchLatest() async {
    final rate = _pendingRate;
    final completion = _completion;
    if (_disposed || rate == null || completion == null) return;
    _pendingRate = null;
    final generation = _generation;
    final revision = _revision;
    bool isCurrent() =>
        !_disposed && generation == _generation && revision == _revision;
    _inFlight++;
    try {
      await apply(rate, isCurrent);
      if (isCurrent()) {
        _confirmedRate = rate;
        onConfirmed(rate);
        if (identical(_completion, completion)) _completion = null;
        if (!completion.isCompleted) completion.complete();
      }
    } catch (error, stack) {
      // 旧请求的迟到失败不能影响已经发出的恢复请求。
      if (isCurrent() && identical(_completion, completion)) {
        _completion = null;
        _confirmedRate = null;
        if (!completion.isCompleted) completion.completeError(error, stack);
      }
    } finally {
      _inFlight--;
    }
  }
}
