import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/hub_transfer_meter.dart';

void main() {
  test('real progress is unknown without a declared total', () {
    final meter = HubTransferMeter();
    expect(meter.update(500).progress, isNull);
    expect(meter.update(500, total: 1000).progress, .5);
    expect(meter.update(1500, total: 1000).progress, 1.0);
  });

  test('throughput uses elapsed time across rapid small chunks', () {
    var now = DateTime(2026);
    final meter = HubTransferMeter(clock: () => now);
    meter.update(0, total: 10000);
    for (var i = 1; i <= 4; i++) {
      now = now.add(const Duration(milliseconds: 50));
      meter.update(i * 500, total: 10000);
    }
    expect(meter.snapshot.receivedBytes, 2000);
    expect(meter.snapshot.bytesPerSecond, closeTo(10000, 1));
    expect(meter.snapshot.progress, .2);
  });

  test('restarting a transfer resets stale speed', () {
    var now = DateTime(2026);
    final meter = HubTransferMeter(clock: () => now);
    meter.update(1000, total: 2000);
    now = now.add(const Duration(seconds: 1));
    expect(meter.update(1500, total: 2000).bytesPerSecond, 500);
    expect(meter.update(0, total: 2000).bytesPerSecond, isNull);
  });
}
