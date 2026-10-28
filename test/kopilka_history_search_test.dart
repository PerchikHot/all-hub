import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  final purchase = <String, dynamic>{
    'kind': 'expense',
    'bank': 'Ozon Банк',
    'note': 'Продукты',
    'date': '2026-10-28T12:00:00',
    'amount': 1250.50,
  };
  final transfer = <String, dynamic>{
    'kind': 'transfer',
    'from': 'Т-Банк',
    'to': 'Газпромбанк',
    'date': '2026-10-27',
  };

  test('finds note and bank without case sensitivity', () {
    expect(matchesKopilkaHistory(purchase, '  OZON   продукты '), isTrue);
    expect(matchesKopilkaHistory(purchase, 'другая покупка'), isFalse);
  });

  test('finds transfers by destination and date', () {
    expect(matchesKopilkaHistory(transfer, 'газпромбанк 2026-10-27'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'перевод т-банк'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'наличные'), isFalse);
  });

  test('finds transaction by amount without exposing saved data', () {
    expect(matchesKopilkaHistory(purchase, '1250.5'), isTrue);
    expect(matchesKopilkaHistory(purchase, '9999'), isFalse);
  });

  test('blank query preserves every transaction including legacy entries', () {
    expect(matchesKopilkaHistory(purchase, ' '), isTrue);
    expect(matchesKopilkaHistory(<String, dynamic>{}, ''), isTrue);
  });
}
