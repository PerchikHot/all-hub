import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('monthly category totals exclude transfers and income', () {
    final transactions = <Map<String, dynamic>>[
      {'kind': 'expense', 'category': 'Продукты', 'amount': 250.5},
      {'kind': 'expense', 'category': 'Продукты', 'amount': 49.5},
      {'kind': 'expense', 'category': 'Транспорт', 'amount': 100},
      {'kind': 'transfer', 'category': 'Продукты', 'amount': 5000},
      {'kind': 'income', 'category': 'Продукты', 'amount': 10000},
      {'kind': 'expense', 'amount': 75},
    ];
    final result = summarizeKopilkaExpenses(transactions);
    expect(result['Продукты'], 300);
    expect(result['Транспорт'], 100);
    expect(result['Без категории'], 75);
    expect(result.values.reduce((a, b) => a + b), 475);
    expect(transactions.last.containsKey('category'), isFalse);
  });

  test('invalid legacy categories and amounts cannot corrupt analytics', () {
    final result = summarizeKopilkaExpenses([
      {'kind': 'expense', 'category': 'Другое', 'amount': 10},
      {'kind': 'expense', 'category': 'Другое', 'amount': double.nan},
      {'kind': 'expense', 'category': 'Другое', 'amount': -100},
      {'kind': 'expense', 'category': 'fake', 'amount': 20},
      {'kind': 'expense', 'category': 42, 'amount': 30},
    ]);
    expect(result['Другое'], 10);
    expect(result['Без категории'], 50);
    expect(kopilkaExpenseCategory({'category': 'Продукты'}), 'Продукты');
    expect(kopilkaExpenseCategory({'category': 'unknown'}), 'Без категории');
    expect(summarizeKopilkaExpenses([]), isEmpty);
  });

  test('salary forecast excludes transfers and income, uses observed days', () {
    final forecast = forecastKopilkaToPayday([
      {'kind': 'expense', 'amount': 500, 'date': '2026-10-26T12:00:00'},
      {'kind': 'income', 'amount': 1000, 'date': '2026-10-28T12:00:00'},
      {'kind': 'transfer', 'amount': 9000, 'date': '2026-10-29T12:00:00'},
      {'kind': 'expense', 'amount': -200, 'date': '2026-10-30T12:00:00'},
      {'kind': 'expense', 'amount': 800, 'date': '2026-11-01T12:00:00'},
    ], DateTime(2026, 10, 30), 10, 2000);
    expect(forecast.nextPayday, DateTime.utc(2026, 11, 10));
    expect(forecast.daysRemaining, 11);
    expect(forecast.observedDays, 5);
    expect(forecast.dailyExpenses, 100);
    expect(forecast.projectedExpenses, 1100);
    expect(forecast.projectedBalance, 900);
  });

  test('payday 31 uses last calendar day in a short month', () {
    final february = forecastKopilkaToPayday(
      [], DateTime(2026, 2, 27), 31, 2500);
    expect(february.nextPayday, DateTime.utc(2026, 2, 28));
    expect(february.daysRemaining, 1);
    expect(february.observedDays, 0);
    expect(february.projectedBalance, 2500);
    final nextMonth = forecastKopilkaToPayday(
      [], DateTime(2026, 2, 28), 31, 2500);
    expect(nextMonth.nextPayday, DateTime.utc(2026, 3, 31));
  });

  test('forecast ignores invalid and older legacy dates', () {
    final forecast = forecastKopilkaToPayday([
      {'kind': 'expense', 'amount': 900, 'date': 'invalid'},
      {'kind': 'expense', 'amount': 300, 'date': '2026-01-01'},
      {'kind': 'expense', 'amount': double.nan, 'date': '2026-10-30'},
    ], DateTime(2026, 10, 30), 10, 100);
    expect(forecast.observedDays, 1);
    expect(forecast.dailyExpenses, 0);
    expect(forecast.projectedBalance, 100);
  });
}
