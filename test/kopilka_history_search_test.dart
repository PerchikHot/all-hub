import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('editing an imported transaction preserves its identity and date', () {
    final original = <String, dynamic>{
      'kind': 'expense', 'amount': 250.0, 'bank': 'Т-Банк',
      'category': 'Продукты', 'note': 'Старое',
      'date': '2026-10-28T12:00:00', 'notificationKey': 'event-123',
    };
    final edited = revisedKopilkaEntry(original,
      kind: 'transfer', amount: 500.0, bank: 'Т-Банк',
      destination: 'Ozon Банк', category: 'Другое', note: '  Пополнение  ');
    expect(edited['kind'], 'transfer');
    expect(edited['from'], 'Т-Банк');
    expect(edited['to'], 'Ozon Банк');
    expect(edited['amount'], 500.0);
    expect(edited['note'], 'Пополнение');
    expect(edited.containsKey('category'), isFalse);
    expect(edited['date'], original['date']);
    expect(edited['notificationKey'], 'event-123');
    expect(original['amount'], 250.0);
    expect(original['kind'], 'expense');
    expect(() => revisedKopilkaEntry(original,
      kind: 'transfer', amount: 50.0, bank: 'Т-Банк',
      destination: 'Т-Банк', category: 'Другое', note: ''), throwsArgumentError);
    expect(() => revisedKopilkaEntry(original,
      kind: 'expense', amount: double.nan, bank: 'Т-Банк',
      destination: 'Ozon Банк', category: 'Другое', note: ''), throwsArgumentError);
  });

  test('filtered net excludes own-account transfers and invalid legacy amounts', () {
    final visible = <Map<String, dynamic>>[
      {'kind': 'income', 'amount': 2000.0},
      {'kind': 'expense', 'amount': 500.25},
      {'kind': 'transfer', 'amount': 9000.0},
      {'kind': 'income', 'amount': double.nan},
      {'kind': 'expense', 'amount': 'not a number'},
    ];
    expect(kopilkaNetChange(visible), closeTo(1499.75, 0.001));
    expect(visible[2]['amount'], 9000.0);
    expect(kopilkaNetChange([]), 0.0);
  });
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

  test('has:date and has:no-date find malformed legacy dates locally', () {
    final valid = {'date': '2026-10-28T12:00:00', 'note': 'A'};
    final missing = {'date': '', 'note': 'B'};
    final invalid = {'date': '2026-02-30', 'note': 'C'};
    expect(matchesKopilkaHistory(valid, 'has:date'), isTrue);
    expect(matchesKopilkaHistory(valid, 'has:no-date'), isFalse);
    expect(matchesKopilkaHistory(missing, 'has:no-date'), isTrue);
    expect(matchesKopilkaHistory(invalid, 'has:no-date'), isTrue);
    expect(matchesKopilkaHistory(invalid, 'has:date'), isFalse);
    expect(matchesKopilkaHistory({'date': '2026-02-28'}, 'has:date'), isTrue);
    expect(matchesKopilkaHistory({'date': '2026-02-29'}, 'has:no-date'), isTrue);
    expect(matchesKopilkaHistory({'date': '2024-02-29'}, 'has:date'), isTrue);
    expect(matchesKopilkaHistory({'date': 'not a date', 'note': '2026-10-28'}, 'has:date'), isFalse);
    expect(matchesKopilkaHistory({'date': null}, 'has:no-date'), isTrue);
    expect(matchesKopilkaHistory(valid, 'has:unknown'), isFalse);
    expect(valid['date'], '2026-10-28T12:00:00');
  });

  test('has:amount and has:no-amount identify malformed imported sums locally', () {
    final valid = <String, dynamic>{'kind': 'expense', 'amount': 1250.50};
    final zero = <String, dynamic>{'kind': 'transfer', 'amount': 0};
    final missing = <String, dynamic>{'kind': 'expense', 'amount': null};
    final invalid = <String, dynamic>{'kind': 'income', 'amount': 'oops'};
    final negative = <String, dynamic>{'kind': 'expense', 'amount': -5};
    final nonFinite = <String, dynamic>{'kind': 'income', 'amount': double.infinity};
    expect(matchesKopilkaHistory(valid, 'has:amount'), isTrue);
    expect(matchesKopilkaHistory(zero, 'has:amount'), isTrue);
    for (final entry in [missing, invalid, negative, nonFinite]) {
      expect(matchesKopilkaHistory(entry, 'has:no-amount'), isTrue);
      expect(matchesKopilkaHistory(entry, 'has:amount'), isFalse);
    }
    expect(matchesKopilkaHistory(valid, 'has:no-amount'), isFalse);
    expect(matchesKopilkaHistory(valid, 'has:unknown'), isFalse);
    expect(valid['amount'], 1250.50);
  });

  test('same-account filter flags suspicious self-transfers without mutation', () {
    final duplicate = <String, dynamic>{
      'kind': 'transfer', 'from': ' Т-Банк ', 'to': 'т-банк',
    };
    final incomplete = <String, dynamic>{
      'kind': 'transfer', 'from': '', 'to': 'Т-Банк',
    };
    expect(matchesKopilkaHistory(duplicate, 'has:same-account'), isTrue);
    expect(matchesKopilkaHistory(duplicate, 'has:different-accounts'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'has:different-accounts'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'has:same-account'), isFalse);
    expect(matchesKopilkaHistory(incomplete, 'has:same-account'), isFalse);
    expect(matchesKopilkaHistory(incomplete, 'has:different-accounts'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'has:same-account'), isFalse);
    expect(duplicate['from'], ' Т-Банк ');
  });

  test('legacy bank labels are compared conservatively for transfer audits', () {
    final legacy = <String, dynamic>{
      'kind': 'transfer', 'from': ' Тинькофф ', 'to': 'т-банк',
    };
    final ozon = <String, dynamic>{
      'kind': 'transfer', 'from': 'Ozon Bank', 'to': 'Озон Банк',
    };
    final differentCards = <String, dynamic>{
      'kind': 'transfer', 'from': 'Т-Банк карта 1', 'to': 'Т-Банк карта 2',
    };
    expect(matchesKopilkaHistory(legacy, 'has:same-account'), isTrue);
    expect(matchesKopilkaHistory(ozon, 'has:same-account'), isTrue);
    expect(matchesKopilkaHistory(differentCards, 'has:different-accounts'), isTrue);
    expect(canonicalKopilkaAccountLabel(' Газпром '), 'газпромбанк');
    expect(canonicalKopilkaAccountLabel('Т-Банк  карта 1'), 'т-банк карта 1');
    expect(legacy['from'], ' Тинькофф ');
  });

  test('has:bank and has:no-bank find unassigned accounts without changing data', () {
    final missing = {'kind': 'expense', 'note': 'Т-Банк в заметке', 'bank': ''};
    final partial = {'kind': 'transfer', 'from': '', 'to': 'Ozon Банк'};
    final unknown = {'kind': 'transfer', 'from': null, 'to': ' '};
    expect(matchesKopilkaHistory(purchase, 'has:bank'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'has:no-bank'), isFalse);
    expect(matchesKopilkaHistory(missing, 'has:no-bank'), isTrue);
    expect(matchesKopilkaHistory(missing, 'has:bank'), isFalse);
    expect(matchesKopilkaHistory(partial, 'has:bank'), isTrue);
    expect(matchesKopilkaHistory(unknown, 'has:no-bank'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'has:bank'), isTrue);
    expect(missing['note'], 'Т-Банк в заметке');
  });

  test('from:/to: filter only the direction of a saved transfer', () {
    expect(matchesKopilkaHistory(transfer, 'from:т-банк to:газпром'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'откуда:т-банк куда:газпром'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'from:газпромбанк'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'to:т-банк'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'from:'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'from:ozon'), isFalse);
    final noteOnly = <String, dynamic>{
      'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Ozon Банк',
      'note': 'Газпромбанк упомянут в комментарии',
    };
    expect(matchesKopilkaHistory(noteOnly, 'to:газпромбанк'), isFalse);
    expect(matchesKopilkaHistory(noteOnly, 'to:ozon'), isTrue);
    expect(noteOnly['to'], 'Ozon Банк');
  });

  test('incomplete transfer count is display-only and excludes purchases', () {
    final records = <Map<String, dynamic>>[
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Ozon Банк'},
      {'kind': 'transfer', 'from': '', 'to': 'Ozon Банк'},
      {'kind': 'transfer', 'from': 'Т-Банк', 'to': null},
      {'kind': 'transfer', 'from': ' ', 'to': ' '},
      {'kind': 'expense', 'bank': 'Т-Банк', 'amount': 250},
    ];
    expect(countIncompleteKopilkaTransfers(records), 3);
    expect(countIncompleteKopilkaTransfers([records.first]), 0);
    expect(countIncompleteKopilkaTransfers([]), 0);
    expect(records[2]['to'], isNull);
    expect(records[3]['from'], ' ');
  });

  test('has:from/to detects incomplete transfers without touching saved data', () {
    final complete = <String, dynamic>{
      'kind': 'transfer', 'from': 'Т-Банк', 'to': 'Ozon Банк',
    };
    final missingFrom = <String, dynamic>{
      'kind': 'transfer', 'from': ' ', 'to': 'Ozon Банк',
    };
    final missingTo = <String, dynamic>{
      'kind': 'transfer', 'from': 'Т-Банк', 'to': null,
    };
    expect(matchesKopilkaHistory(complete, 'has:from has:to'), isTrue);
    expect(matchesKopilkaHistory(complete, 'has:no-from'), isFalse);
    expect(matchesKopilkaHistory(missingFrom, 'has:no-from has:to'), isTrue);
    expect(matchesKopilkaHistory(missingTo, 'has:from has:no-to'), isTrue);
    expect(matchesKopilkaHistory(missingTo, 'has:to'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'has:no-from'), isFalse);
    expect(missingFrom['from'], ' ');
    expect(missingTo['to'], isNull);
  });

  test('has:note and has:no-note inspect descriptions only', () {
    expect(matchesKopilkaHistory(purchase, 'has:note bank:ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'есть:заметка'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'has:no-note'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'has:no-note'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'есть:без-заметки'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'has:note'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'has:unknown'), isFalse);
    expect(purchase['note'], 'Продукты');
  });

  test('note: searches only saved notes, not account names or dates', () {
    expect(matchesKopilkaHistory(purchase, 'note:продукты'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'заметка:продукты bank:ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'note:ozon'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'note:2026-10-28'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'note:'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'заметка:газпромбанк'), isFalse);
    expect(purchase['note'], 'Продукты');
  });

  test('negative terms exclude local matches without changing transactions', () {
    expect(matchesKopilkaHistory(purchase, 'ozon -такси'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'тип:расход -продукты'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'bank:ozon -газпром'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'тип:перевод -т-банк'), isFalse);
    expect(matchesKopilkaHistory(purchase, '-'), isFalse);
    expect(purchase['note'], 'Продукты');
  });

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

  test('type filter matches saved kind rather than a word in the note', () {
    expect(matchesKopilkaHistory(purchase, 'тип:расход ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'type:expense min:1000'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'тип:перевод т-банк'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'type:transfer'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'тип:доход'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'type:expense'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'тип:'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'type:unknown'), isFalse);
    final misleadingNote = <String, dynamic>{
      'kind': 'expense', 'note': 'Перевод на оплату', 'amount': 250,
    };
    expect(matchesKopilkaHistory(misleadingNote, 'тип:перевод'), isFalse);
  });

  test('bank: filters only actual accounts and supports legacy aliases', () {
    expect(matchesKopilkaHistory(purchase, 'bank:ozon тип:расход'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'банк:т-банк'), isTrue);
    expect(matchesKopilkaHistory(transfer, 'bank:gazprombank'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'bank:тинькофф'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'bank:'), isFalse);
    final misleading = <String, dynamic>{
      'kind': 'expense', 'bank': 'Т-Банк', 'note': 'Оплата Ozon', 'amount': 300,
    };
    expect(matchesKopilkaHistory(misleading, 'bank:ozon'), isFalse);
    expect(matchesKopilkaHistory(misleading, 'bank:тбанк'), isTrue);
    expect(misleading['note'], 'Оплата Ozon');
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

  test('date filter matches saved calendar day, not dates in notes', () {
    expect(matchesKopilkaHistory(purchase, 'date:2026-10-28'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'дата:28.10.2026 ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'date:2026-10-27'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'date:2026-02-30'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'date:invalid'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'дата:'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'date:2026-10-27'), isTrue);
    final noteOnly = <String, dynamic>{
      'kind': 'expense', 'note': 'Встреча 2026-10-28',
      'date': '2026-10-29', 'amount': 500,
    };
    expect(matchesKopilkaHistory(noteOnly, 'date:2026-10-28'), isFalse);
    expect(noteOnly['date'], '2026-10-29');
  });

  test('inclusive date range filters only the saved calendar day', () {
    expect(matchesKopilkaHistory(purchase, 'since:2026-10-28 until:2026-10-28'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'с:27.10.2026 по:29.10.2026 bank:ozon'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'since:2026-10-29'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'until:2026-10-27'), isFalse);
    expect(matchesKopilkaHistory(transfer, 'с:27.10.2026 по:27.10.2026'), isTrue);
    expect(matchesKopilkaHistory(purchase, 'since:2026-02-30'), isFalse);
    expect(matchesKopilkaHistory(purchase, 'until:'), isFalse);
    final noteOnly = <String, dynamic>{
      'kind': 'expense', 'note': 'Дата 2026-10-28',
      'date': '2026-10-30', 'amount': 100,
    };
    expect(matchesKopilkaHistory(noteOnly, 'until:2026-10-29'), isFalse);
    expect(matchesKopilkaHistory(<String, dynamic>{}, 'since:2026-01-01'), isFalse);
    expect(noteOnly['date'], '2026-10-30');
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
