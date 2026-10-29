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

  test('familiar bank aliases find operations without changing saved names', () {
    expect(matchesKopilkaHistory(purchase, 'озон продукты'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'тинькофф перевод'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'озон'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'тинькофф'), isFalse);
    expect(purchase['bank'], 'Ozon Банк');
    expect(transfer['from'], 'Т-Банк');
  });

  test('cash aliases match accounts but not unrelated notes', () {
    final cash = <String, dynamic>{
      'kind': 'expense', 'bank': 'Наличные', 'note': 'Обед',
      'date': '2026-10-29', 'amount': 450,
    };
    final noteOnly = <String, dynamic>{
      'kind': 'expense', 'bank': 'Т-Банк', 'note': 'Оплата наличными позже',
      'date': '2026-10-29', 'amount': 450,
    };
    expect(matchesKopilkaHistory(cash, 'нал обед'), isTrue);
    expect(matchesKopilkaHistory(cash, 'cash'), isTrue);
    expect(matchesKopilkaHistory(noteOnly, 'нал'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'cash'), isFalse);
  });

  test('Russian е and ё spelling variants find the same local note', () {
    final coffee = <String, dynamic>{
      'kind': 'expense', 'bank': 'Т-Банк',
      'note': 'Кофе и сгущёнка', 'date': '2026-10-29', 'amount': 320,
    };
    final breakfast = <String, dynamic>{
      'kind': 'expense', 'bank': 'Т-Банк',
      'note': 'Завтрак со сгущенкой', 'date': '2026-10-29', 'amount': 250,
    };
    expect(matchesKopilkaHistory(coffee, 'сгущенка'), isTrue);
    expect(matchesKopilkaHistory(breakfast, 'сгущёнкой'), isTrue);
    expect(matchesKopilkaHistory(coffee, 'сгущенка ozon'), isFalse);
    expect(coffee['note'], 'Кофе и сгущёнка');
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

  test('sum: matches exact kopecks, not amounts in notes or dates', () {
    expect(matchesKopilkaHistory(purchase, 'sum:1250.50'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'sum:1 250,50 ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'sum:1250'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'sum:1250.51'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'sum:invalid'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'sum:'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'sum:99999999999999999999999999'), isFalse);
    final noteOnly = <String, dynamic>{
      'note': 'Оплата 1250.50', 'amount': 400, 'kind': 'expense',
    };
    expect(matchesKopilkaHistory(noteOnly, 'sum:1250.50'), isFalse);
  });

  test('min: and max: filter saved amounts inclusively in kopecks', () {
    expect(matchesKopilkaHistory(purchase, 'min:1250.50'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'max:1250.50'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'min:1000 max:1500 ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'min:1250.51'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'max:1250.49'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'min:1 250,50'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'max:1 250,49'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'min:invalid'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'max:-1'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'min:0'), isFalse);
    final noteOnly = <String, dynamic>{
      'kind': 'expense', 'note': 'Оплата 9999', 'amount': 250,
    };
    expect(matchesKopilkaHistory(noteOnly, 'min:500'), isFalse);
    expect(matchesKopilkaHistory(noteOnly, 'max:500'), isTrue);
  });

  test('blank query preserves every transaction including legacy entries', () {
    expect(matchesKopilkaHistory(purchase, ' '), isTrue);
    expect(matchesKopilkaHistory(<String, dynamic>{}, ''), isTrue);
  });

  test('bank aliases work for both old and new stored bank names', () {
    final oldTinkoff = <String, dynamic>{'bank': 'Тинькофф', 'kind': 'expense'};
    final oldOzon = <String, dynamic>{'bank': 'Озон Банк', 'kind': 'expense'};
    final latinGazprom = <String, dynamic>{'bank': 'Gazprombank', 'kind': 'income'};
    expect(matchesKopilkaHistory(oldTinkoff, 'т-банк'), isTrue);
    expect(matchesKopilkaHistory(oldTinkoff, 'тбанк'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'тбанк перевод'), isTrue);
    expect(matchesKopilkaHistory(oldOzon, 'ozon'), isTrue);
    expect(matchesKopilkaHistory(latinGazprom, 'газпром'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'gazprombank'), isTrue);
    expect(matchesKopilkaHistory(oldTinkoff, 'ozon'), isFalse);
    expect(oldTinkoff['bank'], 'Тинькофф');
  });
}
