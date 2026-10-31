import 'package:all_hub/kopilka_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmed bank alert keeps original Android posting time', () {
    final reviewedAt = DateTime(2026, 10, 31, 18, 0);
    final postedAt = DateTime(2026, 10, 30, 12, 45);
    final result = kopilkaConfirmedNotificationDate(
        {'time': postedAt.millisecondsSinceEpoch}, reviewedAt);
    expect(result, postedAt);
    final trend = kopilkaDailyExpenseTrend([
      {'kind': 'expense', 'amount': 450.0, 'date': result.toIso8601String()},
    ], reviewedAt, days: 3);
    expect(trend, [0.0, 450.0, 0.0]);
  });

  test('malformed, ancient and future timestamps use confirmation time', () {
    final now = DateTime(2026, 10, 31, 18, 0);
    for (final payload in <Map<String, dynamic>?>[
      null, {}, {'time': '1760000000000'}, {'time': -1},
      {'time': 946684799999},
      {'time': now.millisecondsSinceEpoch + 6 * 60 * 1000},
    ]) {
      expect(kopilkaConfirmedNotificationDate(payload, now), now);
    }
    expect(kopilkaConfirmedNotificationDate(
        {'time': now.millisecondsSinceEpoch + 4 * 60 * 1000}, now),
        DateTime.fromMillisecondsSinceEpoch(
            now.millisecondsSinceEpoch + 4 * 60 * 1000));
  });

  test('manual transactions use their actual confirmation time', () {
    final now = DateTime(2026, 10, 31, 18, 0);
    expect(kopilkaConfirmedNotificationDate(null, now), now);
  });
}
