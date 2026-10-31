import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('seven-day expenses exclude transfers, income, future and corrupt rows', () {
    final rows = <Map<String, dynamic>>[
      {'kind': 'expense', 'amount': 120.5, 'date': '2026-10-25T09:00:00'},
      {'kind': 'expense', 'amount': 80, 'date': '2026-10-31T20:00:00'},
      {'kind': 'expense', 'amount': 20, 'date': '2026-10-31T21:00:00'},
      {'kind': 'income', 'amount': 900, 'date': '2026-10-31'},
      {'kind': 'transfer', 'amount': 1000, 'date': '2026-10-31'},
      {'kind': 'expense', 'amount': 10, 'date': '2026-10-24'},
      {'kind': 'expense', 'amount': 300, 'date': '2026-11-01'},
      {'kind': 'expense', 'amount': -40, 'date': '2026-10-31'},
      {'kind': 'expense', 'amount': 'invalid', 'date': '2026-10-31'},
      {'kind': 'expense', 'amount': 40, 'date': 'bad-date'},
    ];
    final result = kopilkaDailyExpenseTrend(rows, DateTime(2026, 10, 31));
    expect(result, [120.5, 0, 0, 0, 0, 0, 100]);
    expect(rows.length, 10); // Read-only analytics never rewrites history.
  });

  test('calendar dates remain correct across month and leap-year boundaries', () {
    final rows = <Map<String, dynamic>>[
      {'kind': 'expense', 'amount': 11, 'date': '2024-02-29'},
      {'kind': 'expense', 'amount': 7, 'date': '2024-03-01'},
    ];
    expect(kopilkaDailyExpenseTrend(rows, DateTime(2024, 3, 1), days: 2),
      [11, 7]);
    expect(() => kopilkaDailyExpenseTrend(rows, DateTime.now(), days: 0),
      throwsArgumentError);
  });
}
