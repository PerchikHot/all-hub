import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  const banks = ['Т-Банк', 'Газпромбанк', 'Ozon Банк'];
  test('internal transfers move between accounts without inflating income', () {
    final flows = summarizeKopilkaAccountFlows([
      {'kind': 'income', 'bank': 'Т-Банк', 'amount': 10000},
      {'kind': 'expense', 'bank': 'Т-Банк', 'amount': 1500},
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Ozon Банк',
       'amount': 2000},
      {'kind': 'expense', 'bank': 'Ozon Банк', 'amount': 300},
    ], banks);
    expect(flows['Т-Банк']!.income, 10000);
    expect(flows['Т-Банк']!.expense, 1500);
    expect(flows['Т-Банк']!.transfersOut, 2000);
    expect(flows['Т-Банк']!.net, 6500);
    expect(flows['Ozon Банк']!.income, 0);
    expect(flows['Ozon Банк']!.transfersIn, 2000);
    expect(flows['Ozon Банк']!.net, 1700);
    expect(flows.values.fold<double>(0, (sum, flow) => sum + flow.net), 8200);
  });

  test('unknown, incomplete, self and invalid transfers are ignored', () {
    final flows = summarizeKopilkaAccountFlows([
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': '', 'amount': 9000},
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Т-Банк', 'amount': 9000},
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Unknown', 'amount': 9000},
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Ozon Банк',
       'amount': double.nan},
      {'kind': 'expense', 'bank': 'Т-Банк', 'amount': -200},
      {'kind': 'income', 'bank': 'Unknown', 'amount': 500},
      {'kind': 'expense', 'bank': 'Т-Банк', 'amount': 100},
    ], banks);
    expect(flows['Т-Банк']!.net, -100);
    expect(flows['Ozon Банк']!.net, 0);
    expect(flows['Газпромбанк']!.net, 0);
  });
}
