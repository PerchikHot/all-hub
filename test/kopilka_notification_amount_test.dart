import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('pending bank notifications require a stable unique unreviewed key', () {
    final alerts = <dynamic>[
      {'key': 'a', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'key': 'a', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'key': 'b', 'title': 'Ozon Банк', 'body': 'Перевод 2 000 ₽'},
      {'key': 'c', 'title': 'Банк', 'body': 'Код подтверждения оплаты 500 ₽'},
      {'title': 'Банк', 'body': 'Оплата 100 ₽'},
      'malformed',
      {42: 'invalid native key'},
      {'key': 123, 'title': 'Т-Банк', 'body': 'Оплата 200 ₽'},
      {'key': '   ', 'title': 'Т-Банк', 'body': 'Оплата 300 ₽'},
      {'key': ' b ', 'title': 'Ozon Банк', 'body': 'Перевод 2 000 ₽'},
    ];
    expect(filterPendingBankNotifications(alerts, <String>{}).map((e) => e['key']).toList(),
      ['a', 'b']);
    expect(filterPendingBankNotifications(alerts, <String>{'a'}).map((e) => e['key']).toList(),
      ['b']);
    expect(filterPendingBankNotifications(alerts, <String>{'b'}).map((e) => e['key']).toList(),
      ['a']);
    final padded = <dynamic>[
      {'key': '  tx-42  ', 'title': 'Т-Банк', 'body': 'Оплата 125 ₽'},
    ];
    expect(filterPendingBankNotifications(padded, <String>{}).single['key'], 'tx-42');
    expect(filterPendingBankNotifications(padded, <String>{'tx-42'}), isEmpty);
    expect(filterPendingBankNotifications(padded, <String>{' tx-42 '}), isEmpty);
  });

  test('oversized or non-text native bank alerts are not imported', () {
    final valid = {'key': 'ok', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'};
    final alerts = <dynamic>[
      {'key': 'large-key-${List.filled(260, 'x').join()}',
       'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'key': 'line\nbreak', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'key': 'tab\tkey', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'key': 'bad-title', 'title': {'bank': 'Т-Банк'},
       'body': 'Оплата 250 ₽'},
      {'key': 'bad-body', 'title': 'Т-Банк', 'body': ['Оплата 250 ₽']},
      {'key': 'long-title', 'title': List.filled(201, 'x').join(),
       'body': 'Оплата 250 ₽'},
      {'key': 'long-body', 'title': 'Т-Банк',
       'body': 'Оплата 250 ₽${List.filled(2050, 'x').join()}'},
      valid,
    ];
    final accepted = filterPendingBankNotifications(alerts, <String>{});
    expect(accepted.map((e) => e['key']).toList(), ['ok']);
    expect(valid['body'], 'Оплата 250 ₽');
  });

  test('scheduled payment reminders are not posted transaction suggestions', () {
    for (final body in [
      'Запланирована оплата 250 ₽ на завтра',
      'Перевод 500 ₽ планируется завтра',
      'Завтра будет списано 300 ₽',
      'Payment 200 RUB scheduled for tomorrow',
      'Upcoming transfer 150 RUB',
      'Оплата 450 ₽ ожидается завтра',
      'Завтра будет оплата 200 ₽',
      'Payment 300 RUB will be charged tomorrow',
    ]) {
      expect(isBankTransactionNotification('Банк', body), isFalse,
          reason: body);
    }
    expect(isBankTransactionNotification('Банк', 'Оплата 250 ₽ выполнена'),
        isTrue);
  });

  group('Kopilka transaction notification privacy filter', () {
    test('keeps purchase, transfer and incoming money notifications', () {
      expect(isBankTransactionNotification('Т-Банк', 'Оплата 250 ₽. Остаток 5 000 ₽'), isTrue);
      expect(isBankTransactionNotification('Ozon Банк', 'Перевод 2 000 RUB'), isTrue);
      expect(isBankTransactionNotification('Газпромбанк', 'Зачисление 500 рублей'), isTrue);
      expect(isBankTransactionNotification('Т-Банк', 'Оплата 1 рубль'), isTrue);
    });

    test('does not offer balance-only or promotional alerts', () {
      expect(isBankTransactionNotification('Т-Банк', 'Остаток 5 000 ₽'), isFalse);
      expect(isBankTransactionNotification('Акция', 'Скидка 100 ₽'), isFalse);
      expect(isBankTransactionNotification('Т-Банк', 'Оплата в рублях завершена'), isFalse);
      expect(isBankTransactionNotification('Т-Банк', 'Перевод RUB успешно выполнен'), isFalse);
      expect(isBankTransactionNotification('Ozon Банк', 'Оплата 125,50 руб.'), isTrue);
    });

    test('declined and cancelled transactions are not suggested as expenses', () {
      for (final body in [
        'Оплата 450 ₽ отклонена банком',
        'Покупка 1 200 ₽ не прошла',
        'Списание 500 ₽ не выполнено',
        'Перевод 1000 RUB отменен',
        'Оплата 350 ₽: недостаточно средств',
        'Payment 300 RUB declined',
        'Transfer 250 RUB failed',
        'Purchase 150 RUB canceled',
        'Оплата 450 ₽ ожидает подтверждения',
        'Перевод 1000 ₽ в обработке',
        'Payment 200 RUB pending',
        'Transfer 300 RUB processing',
        'Payment 150 RUB awaiting approval',
        'Оплата 300 ₽: отказано банком',
        'Перевод 250 ₽ не одобрен',
        'Ошибка оплаты 500 ₽',
        'Payment 250 RUB insufficient funds',
        'Оплата 300 ₽ требует подтверждения',
        'Подтвердите перевод 500 ₽',
        'Payment 200 RUB requires confirmation',
        'Payment 200 RUB authorization required',
      ]) {
        expect(isBankTransactionNotification('Банк', body), isFalse,
            reason: body);
      }
      expect(isBankTransactionNotification('Т-Банк',
          'Оплата 450 ₽ выполнена'), isTrue);
      expect(isBankTransactionNotification('Ozon Банк',
          'Возврат 300 ₽ за покупку'), isTrue);
    });

    test('blocked or suspended payments are not completed expenses', () {
      for (final body in [
        'Оплата 500 ₽ заблокирована',
        'Перевод 250 ₽ приостановлен',
        'Списание 100 ₽ заморожено',
        'Payment 300 RUB blocked',
        'Transfer 200 RUB suspended',
        'Payment 150 RUB on hold',
      ]) {
        expect(isBankTransactionNotification('Банк', body), isFalse,
            reason: body);
      }
      expect(isBankTransactionNotification('Банк', 'Оплата 500 ₽ выполнена'),
          isTrue);
    });

    test('unposted and unconfirmed payments are not treated as completed', () {
      for (final body in [
        'Оплата 400 ₽ не проведена',
        'Перевод 500 ₽ не подтвержден',
        'Платёж 300 ₽ не завершён',
        'Оплата 200 ₽ не состоялась',
        'Payment 400 RUB not completed',
        'Transfer 200 RUB not processed',
        'Payment 150 RUB not approved',
      ]) {
        expect(isBankTransactionNotification('Банк', body), isFalse,
            reason: body);
      }
      expect(isBankTransactionNotification('Банк', 'Оплата 200 ₽ проведена'),
          isTrue);
    });

    test('does not import payment alerts containing credentials', () {
      for (final body in [
        'Пароль для оплаты 200 ₽: 1234',
        'Payment 200 RUB. Your password is 1234',
        'PIN для перевода 500 ₽',
        'CVV для оплаты 300 ₽',
        'Код безопасности: 456. Оплата 100 ₽',
        'Ваш код: 1234. Оплата 250 ₽',
        'Payment 250 RUB. Your code: 9999',
        'Код: 4321. Перевод 2 000 ₽',
      ]) {
        expect(isBankTransactionNotification('Банк', body), isFalse,
            reason: body);
      }
      expect(isBankTransactionNotification('Т-Банк', 'Оплата 300 ₽'), isTrue);
    });

    test('never offers login and transaction confirmation codes', () {
      expect(isBankTransactionNotification('Т-Банк', 'Код подтверждения перевода 1 000 ₽: 1234'), isFalse);
      expect(isBankTransactionNotification('Ozon', 'Никому не сообщайте код. Оплата 200 ₽'), isFalse);
      expect(isBankTransactionNotification('Bank', 'Verification code for payment 200 RUB'), isFalse);
      expect(isBankTransactionNotification('Т-Банк', 'Код для подтверждения перевода 1 000 ₽: 1234'), isFalse);
      expect(isBankTransactionNotification('Газпромбанк', 'СМС-код для оплаты 500 ₽: 1234'), isFalse);
      expect(isBankTransactionNotification('Ozon Банк', 'Код операции: 1234. Перевод 2 000 ₽'), isFalse);
      expect(isBankTransactionNotification('Т-Банк', 'Код из СМС для оплаты 300 ₽'), isFalse);
    });
  });

  group('Kopilka notification operation type suggestions', () {
    test('incoming credit suggests income', () {
      expect(suggestNotificationKind('Зачисление 2 500 ₽'), 'income');
      expect(suggestNotificationKind('Поступило 1000 рублей'), 'income');
    });

    test('refund and top-up suggest income', () {
      expect(suggestNotificationKind('Возврат 450 ₽'), 'income');
      expect(suggestNotificationKind('Пополнение Ozon Банка'), 'income');
    });

    test('purchases and debits remain expenses', () {
      expect(suggestNotificationKind('Оплата 250 ₽'), 'expense');
      expect(suggestNotificationKind('Списание 300 ₽'), 'expense');
    });

    test('ambiguous transfer is never automatically classified as income', () {
      expect(suggestNotificationKind('Перевод 2 000 ₽'), 'expense');
      expect(suggestNotificationKind('Перевод. Поступление 2 000 ₽'), 'expense');
    });

    test('balance-only and unknown notifications default to expense review', () {
      expect(suggestNotificationKind('Остаток 4 000 ₽'), 'expense');
      expect(suggestNotificationKind('Новое уведомление'), 'expense');
    });
  });

  group('Kopilka bank notification amount suggestions', () {
    test('recognizes a purchase before the remaining balance', () {
      expect(suggestNotificationAmount('Оплата 250 ₽. Остаток 5 000 ₽'), '250');
    });

    test('recognizes a purchase after the remaining balance', () {
      expect(suggestNotificationAmount('Остаток 5 000 ₽. Покупка 250 ₽'), '250');
    });

    test('does not suggest a balance-only notification as an expense', () {
      expect(suggestNotificationAmount('Доступно 12 500 ₽'), isEmpty);
    });

    test('handles narrow no-break spaces and decimal commas', () {
      expect(suggestNotificationAmount('Списание 1\u202f234,50 ₽'), '1234.50');
    });

    test('handles rubles spelled out', () {
      expect(suggestNotificationAmount('Поступило 2 500 рублей'), '2500');
    });

    test('recognizes singular and plural ruble forms in notifications', () {
      expect(suggestNotificationAmount('Оплата 1 рубль'), '1');
      expect(suggestNotificationAmount('Оплата 2 рубля'), '2');
      expect(suggestNotificationAmount('Оплата 5 рублей'), '5');
      expect(suggestNotificationAmount('Остаток 1 рубль'), isEmpty);
    });

    test('uses the nearest label when the amount precedes its action', () {
      expect(suggestNotificationAmount('250 ₽ списание. 1000 ₽ остаток'), '250');
    });

    test('ignores zero-value alerts and still finds a later valid amount', () {
      expect(suggestNotificationAmount('Оплата 0 ₽'), isEmpty);
      expect(isBankTransactionNotification('Т-Банк', 'Оплата 0 ₽'), isFalse);
      expect(suggestNotificationAmount('Оплата 0 ₽. Покупка 250 ₽'), '250');
      expect(isBankTransactionNotification('Т-Банк', 'Покупка 0,00 руб.'), isFalse);
    });

    test('allows a standalone currency amount for manual confirmation', () {
      expect(suggestNotificationAmount('1 200 RUB'), '1200');
    });
  });
  group('Kopilka manual amount validation', () {
    test('accepts grouped ruble amounts and decimal commas', () {
      expect(parseKopilkaAmount('1 250,50'), 1250.5);
      expect(parseKopilkaAmount('12\u202f500.25'), 12500.25);
      expect(parseKopilkaAmount('1234.5'), 1234.5);
      expect(parseKopilkaAmount('1 250,50 ₽'), 1250.5);
      expect(parseKopilkaAmount('2 000 руб.'), 2000.0);
      expect(parseKopilkaAmount('125 RUB'), 125.0);
      expect(parseKopilkaAmount('1 рубль'), 1.0);
      expect(parseKopilkaAmount('2 рубля'), 2.0);
      expect(parseKopilkaAmount('5 рублей'), 5.0);
    });
    test('rejects ambiguous grouping and invalid amounts', () {
      expect(parseKopilkaAmount('1 2'), isNull);
      expect(parseKopilkaAmount('1 23,45'), isNull);
      expect(parseKopilkaAmount('-100'), isNull);
      expect(parseKopilkaAmount('0'), isNull);
      expect(parseKopilkaAmount('100.999'), isNull);
      expect(parseKopilkaAmount('abc'), isNull);
    });
  });

  group('Kopilka saved amount safety', () {
    test('valid numeric amounts remain unchanged', () {
      expect(safeKopilkaAmount({'amount': 120.50}), 120.50);
      expect(safeKopilkaAmount({'amount': 42}), 42.0);
    });
    test('corrupt historical amounts cannot crash or distort totals', () {
      expect(safeKopilkaAmount({'amount': 'not-a-number'}), 0.0);
      expect(safeKopilkaAmount({'amount': null}), 0.0);
      expect(safeKopilkaAmount({'amount': double.infinity}), 0.0);
      expect(safeKopilkaAmount({'amount': double.nan}), 0.0);
      expect(safeKopilkaAmount({'amount': -250}), 0.0);
      expect(kopilkaNetChange([
        {'kind': 'expense', 'amount': -250},
        {'kind': 'income', 'amount': 100},
      ]), 100.0);
    });
  });

  test('listener diagnostics are safe for empty and valid native states', () {
    expect(describeKopilkaListener(null), contains('отдельной Android'));
    expect(describeKopilkaListener({'lastSeen': 0, 'queued': 0}),
        contains('ещё не получено'));
    final summary = describeKopilkaListener({
      'lastSeen': 1730000000000, 'queued': 2, 'lastBank': 'Т-Банк',
    });
    expect(summary, contains('Т-Банк'));
    expect(summary, contains('в очереди: 2'));
    expect(summary, isNot(contains('код')));
  });

}
