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
}
