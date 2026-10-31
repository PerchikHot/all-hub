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

  test('own-bank transfer hints are read-only and reject ambiguous matches', () {
    final entries = <Map<String, dynamic>>[
      {'kind': 'expense', 'bank': 'Т-Банк', 'amount': 2000,
        'date': '2026-10-31T10:00:00'},
      {'kind': 'income', 'bank': 'Ozon Банк', 'amount': 2000,
        'date': '2026-10-31T10:02:00'},
      {'kind': 'expense', 'bank': 'Т-Банк', 'amount': 50,
        'date': '2026-10-31T10:04:00'},
    ];
    final before = entries.map((e) => Map<String, dynamic>.from(e)).toList();
    final matches = suggestKopilkaOwnTransfers(
      entries, ['Т-Банк', 'Газпромбанк', 'Ozon Банк']);
    expect(matches, hasLength(1));
    expect(matches.single['from'], 'Т-Банк');
    expect(matches.single['to'], 'Ozon Банк');
    expect(matches.single['amount'], 2000.0);
    expect(entries, before);
    entries.add({'kind': 'income', 'bank': 'Газпромбанк', 'amount': 2000,
      'date': '2026-10-31T10:03:00'});
    expect(suggestKopilkaOwnTransfers(
      entries, ['Т-Банк', 'Газпромбанк', 'Ozon Банк']), isEmpty);
    entries.removeLast();
    entries.add({'kind': 'expense', 'bank': 'Газпромбанк', 'amount': 2000,
      'date': '2026-10-31T10:01:00'});
    expect(suggestKopilkaOwnTransfers(
      entries, ['Т-Банк', 'Газпромбанк', 'Ozon Банк']), isEmpty);
    entries.removeLast();
    entries[1]['date'] = '2026-10-31T11:00:00';
    expect(suggestKopilkaOwnTransfers(
      entries, ['Т-Банк', 'Газпромбанк', 'Ozon Банк']), isEmpty);
  });
}
