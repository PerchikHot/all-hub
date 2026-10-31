import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('daily budget allowance includes today and handles month boundaries', () {
    expect(kopilkaDailyBudgetAllowance(100, 410, DateTime(2026, 10, 1)), 10);
    expect(kopilkaDailyBudgetAllowance(200, 300, DateTime(2026, 10, 31)), 100);
    expect(kopilkaDailyBudgetAllowance(0, 280, DateTime(2027, 2, 1)), 10);
    expect(kopilkaDailyBudgetAllowance(0, 290, DateTime(2028, 2, 1)), 10);
    expect(kopilkaDailyBudgetAllowance(350, 300, DateTime(2026, 10, 20)), 0);
    expect(kopilkaDailyBudgetAllowance(100, 0, DateTime(2026, 10, 1)), isNull);
    expect(kopilkaDailyBudgetAllowance(double.nan, 300, DateTime(2026, 10, 1)), isNull);
  });

  test('monthly budget is optional and never blocks transactions', () {
    expect(kopilkaMonthlyBudgetProgress(500, 0), isNull);
    expect(kopilkaMonthlyBudgetProgress(500, -1), isNull);
    expect(kopilkaMonthlyBudgetProgress(500, double.nan), isNull);
    expect(kopilkaMonthlyBudgetProgress(double.infinity, 1000), isNull);
    expect(kopilkaMonthlyBudgetProgress(-10, 1000), isNull);
  });

  test('monthly budget progress is bounded for over-spending', () {
    expect(kopilkaMonthlyBudgetProgress(0, 1000), 0);
    expect(kopilkaMonthlyBudgetProgress(250, 1000), 0.25);
    expect(kopilkaMonthlyBudgetProgress(1000, 1000), 1);
    expect(kopilkaMonthlyBudgetProgress(2000, 1000), 1);
  });

  test('transfers do not inflate the monthly budget expense total', () {
    final expenses = summarizeKopilkaExpenses([
      {'kind': 'expense', 'category': 'Продукты', 'amount': 300},
      {'kind': 'income', 'amount': 900},
      {'kind': 'transfer', 'amount': 2000, 'from': 'Т-Банк', 'to': 'Ozon Банк'},
    ]);
    final spent = expenses.values.fold<double>(0, (sum, value) => sum + value);
    expect(spent, 300);
    expect(kopilkaMonthlyBudgetProgress(spent, 600), 0.5);
  });
}
