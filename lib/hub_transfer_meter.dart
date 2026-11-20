import 'package:flutter/foundation.dart';

@immutable
class HubTransferSnapshot {
  const HubTransferSnapshot({
    required this.receivedBytes,
    this.totalBytes,
    this.bytesPerSecond,
  });
  final int receivedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;

  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null : (receivedBytes / totalBytes!).clamp(0.0, 1.0).toDouble();
}

/// Monotonic transfer telemetry. Uses actual received bytes, never animated
/// guesses; speed is an exponential moving average to avoid UI jitter.
class HubTransferMeter {
  HubTransferMeter({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  DateTime? _lastSample;
  int _lastBytes = 0;
  double? _speed;
  int _received = 0;
  int? _total;

  HubTransferSnapshot get snapshot => HubTransferSnapshot(
    receivedBytes: _received,
    totalBytes: _total,
    bytesPerSecond: _speed,
  );

  HubTransferSnapshot update(int received, {int? total}) {
    final now = _clock();
    final safeReceived = received < 0 ? 0 : received;
    if (safeReceived < _received) {
      _lastSample = null;
      _lastBytes = 0;
      _speed = null;
    }
    _received = safeReceived;
    if (total != null && total >= _received) _total = total;
    final last = _lastSample;
    if (last != null) {
      final seconds = now.difference(last).inMicroseconds / 1000000;
      final delta = _received - _lastBytes;
      if (seconds >= .2 && delta >= 0) {
        final instant = delta / seconds;
        _speed = _speed == null ? instant : _speed! * .7 + instant * .3;
      }
    }
    _lastSample = now;
    _lastBytes = _received;
    return snapshot;
  }
}
