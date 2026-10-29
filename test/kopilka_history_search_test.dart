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

  test('finds ISO-stored dates using Russian date format', () {
    expect(matchesKopilkaHistory(purchase, '28.10.2026'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'ozon 28.10.2026'), isTrue);
    expect(matchesKopilkaHistory(transfer, '27.10.2026'), isTrue);
    expect(matchesKopilkaHistory(purchase, '27.10.2026'), isFalse);
  });

  test('single-digit Russian day and month match stored ISO dates', () {
    final january = <String, dynamic>{
      'kind': 'income',
      'bank': 'Т-Банк',
      'date': '2026-01-08T09:30:00',
      'amount': 2000,
    };
    expect(matchesKopilkaHistory(january, '8.1.2026'), isTrue);
    expect(matchesKopilkaHistory(january, '08.1.2026 т-банк'), isTrue);
    expect(matchesKopilkaHistory(january, '9.1.2026'), isFalse);
    expect(matchesKopilkaHistory(purchase, '28.10.2026'), isTrue);
  });

  test('finds transaction by amount without exposing saved data', () {
    expect(matchesKopilkaHistory(purchase, '1250.5'), isTrue);
    expect(matchesKopilkaHistory(purchase, '9999'), isFalse);
  });

  test('finds Russian formatted sums with bank and note filters', () {
    expect(matchesKopilkaHistory(purchase, '1 250,50'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1\u00a0250,50'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'ozon 1 250,50'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'продукты 1250,5'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1 250,51'), isFalse);
  });

  test('amount searches accept optional currency suffixes', () {
    expect(matchesKopilkaHistory(purchase, '1 250,50 ₽'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1250,50 руб.'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1250,50 рублей'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1250,50 рубля'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1250,50 рубль'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1250,51 рублей'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'ozon 1250.5 RUB'), isTrue);
    expect(matchesKopilkaHistory(purchase, '1250,51 ₽'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'RUB'), isFalse);
  });

  test('blank query preserves every transaction including legacy entries', () {
    expect(matchesKopilkaHistory(purchase, ' '), isTrue);
    expect(matchesKopilkaHistory(<String, dynamic>{}, ''), isTrue);
  });
}
