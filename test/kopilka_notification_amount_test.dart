import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('multiple transaction amounts require manual selection, not guessing', () {
    final body = 'Оплата 100 ₽. Оплата 250 ₽';
    expect(suggestNotificationAmount(body), isEmpty);
    expect(isBankTransactionNotification('Т-Банк', body), isTrue);
    expect(kopilkaPendingReviewPreview({
      'title': 'Т-Банк', 'body': body,
    }), 'Сумма требует проверки');
    expect(suggestNotificationAmount('Оплата 100 ₽. Остаток 250 ₽'), '100');
    expect(suggestNotificationAmount('Оплата 100 ₽. Оплата 100 ₽'), '100');
  });

  test('pending review preview never posts or invents a bank balance', () {
    final payment = <String, dynamic>{
      'title': 'Т-Банк', 'body': 'Оплата 1 250,50 ₽. Остаток 4 000 ₽',
    };
    expect(kopilkaPendingReviewPreview(payment),
      contains('Возможный расход 1250.50 ₽'));
    expect(kopilkaPendingReviewPreview({
      'title': 'Ozon Банк', 'body': 'Зачислено 350 ₽',
    }), contains('Возможный доход 350 ₽'));
    expect(kopilkaPendingReviewPreview({
      'title': 'Газпромбанк', 'body': 'Перевод 500 ₽',
    }), contains('уточнить свои счета'));
    expect(kopilkaPendingReviewPreview({
      'title': 'Т-Банк', 'body': 'Код подтверждения оплаты 500 ₽',
    }), 'Данные требуют ручной проверки');
    expect(kopilkaPendingReviewPreview({'title': 'Банк', 'body': null}),
      'Данные требуют ручной проверки');
    expect(payment['body'], 'Оплата 1 250,50 ₽. Остаток 4 000 ₽');
  });


  test('bank review filters preserve pending alerts and never approve them', () {
    final pending = <Map<String, dynamic>>[
      {'bank': 'Т-Банк', 'key': 'one'},
      {'bank': 'Ozon Банк', 'key': 'two'},
      {'bank': 'Газпромбанк', 'key': 'three'},
      {'bank': 'Т-Банк', 'key': 'four'},
    ];
    expect(filterKopilkaPendingByBank(pending, null), hasLength(4));
    expect(filterKopilkaPendingByBank(pending, 'Т-Банк')
        .map((e) => e['key']).toList(), ['one', 'four']);
    expect(filterKopilkaPendingByBank(pending, 'Ozon Банк'), hasLength(1));
    expect(filterKopilkaPendingByBank(pending, 'unknown'), isEmpty);
    expect(pending, hasLength(4));
  });

  test('listener import counters never reveal notification contents', () {
    expect(describeKopilkaImportGate(null), contains('отдельной Android APK'));
    expect(describeKopilkaImportGate({'accepted': 3, 'filtered': 8}),
        contains('Отобрано для проверки: 3 · отклонено фильтром: 8'));
    expect(describeKopilkaImportGate({'accepted': -1, 'filtered': 0}),
        contains('после обновления'));
  });

  test('queue overflow and recovery are visible without notification contents', () {
    final report = describeKopilkaListener({
      'connected': true, 'lastSeen': 0, 'queued': 100,
      'queueDropped': 3, 'queueRecoveries': 1,
    });
    expect(report, contains('3 уведомлений вытеснено'));
    expect(report, contains('повреждения 1 раз'));
    expect(report, isNot(contains('body')));
    expect(describeKopilkaListener({
      'lastSeen': 0, 'queueDropped': 0, 'queueRecoveries': 0,
    }), isNot(contains('Внимание:')));
  });

  test('native queue disk failure is surfaced without leaking bank data', () {
    final report = describeKopilkaListener({
      'connected': true,
      'lastSeen': 0,
      'lastQueueWriteFailed': 1793540000000,
      'body': 'Код 123456',
    });
    expect(report, contains('не смог сохранить банковское уведомление'));
    expect(report, contains('свободное место'));
    expect(report, isNot(contains('123456')));
    expect(describeKopilkaListener({'connected': true, 'lastSeen': 0}),
        isNot(contains('не смог сохранить')));
  });

  test('listener disconnect diagnostics report rebind attempts without bank text', () {
    final report = describeKopilkaListener({
      'connected': false,
      'lastConnected': DateTime(2026, 10, 31).millisecondsSinceEpoch,
      'lastDisconnected': DateTime(2026, 11, 1).millisecondsSinceEpoch,
      'rebindRequests': 2,
      'lastSeen': 0,
    });
    expect(report, contains('Служба отключена'));
    expect(report, contains('Запросов переподключения: 2'));
    expect(report, contains('01.11'));
    expect(report, isNot(contains('код')));
    expect(describeKopilkaListener({'connected': true, 'lastSeen': 0}),
        contains('Служба уведомлений подключена'));
  });

  test('three banks: posted payment wording and amount extraction', () {
    for (final alert in [
      'Платёж 1 250,50 ₽ выполнен',
      'Платеж 300 RUB исполнен',
      'Оплачено 299 руб.',
      'Платёж 1 рубль проведён',
    ]) {
      expect(isBankTransactionNotification('Т-Банк', alert), isTrue,
          reason: alert);
      expect(suggestNotificationKind(alert), 'expense');
    }
    expect(suggestNotificationAmount('Платёж 1 250,50 ₽. Остаток 4 000 ₽'),
        '1250.50');
    expect(isBankTransactionNotification('Газпромбанк',
        'Платёж 350 ₽ не подтверждён'), isFalse);
    expect(isBankTransactionNotification('Ozon Банк',
        'Платеж 400 ₽ требует подтверждения'), isFalse);
  });

  test('native-filtered unposted alerts also stay out of Dart import', () {
    for (final body in [
      'Оплата 500 ₽ не одобрена',
      'Перевод 200 ₽ не состоялся',
      'Платёж 300 ₽: отказано банком',
      'Ошибка перевода 400 ₽',
      'Оплата 100 ₽ заблокирована',
      'Списание 150 ₽ приостановлено',
      'Оплата 125 ₽ заморожена',
      'Перевод 200 ₽ планируется завтра',
      'Payment 300 RUB awaiting approval',
      'Payment 300 RUB on hold',
      'Payment 300 RUB not processed',
      'Код безопасности для оплаты 500 ₽',
      'Код для оплаты 500 ₽: 1234',
      'Код перевода 500 ₽: 1234',
      'Confirmation code for payment 200 RUB',
      'Security code for transfer 400 RUB',
      'СМС-пароль для оплаты 100 ₽',
    ]) {
      expect(isBankTransactionNotification('Т-Банк', body), isFalse,
          reason: body);
    }
    expect(isBankTransactionNotification('Газпромбанк',
        'Оплата 500 ₽ выполнена'), isTrue);
  });

  test('reviewing one bank notification twice never creates duplicate postings', () {
    final entries = <Map<String, dynamic>>[
      {'kind': 'expense', 'amount': 250.0, 'notificationKey': 'tx-1'},
      {'kind': 'income', 'amount': 100.0, 'notificationKey': ' tx-2 '},
      {'kind': 'expense', 'amount': 50.0},
    ];
    expect(isKopilkaNotificationImported(entries, 'tx-1'), isTrue);
    expect(isKopilkaNotificationImported(entries, ' tx-2'), isTrue);
    expect(isKopilkaNotificationImported(entries, 'tx-3'), isFalse);
    expect(isKopilkaNotificationImported(entries, ''), isFalse);
    expect(isKopilkaNotificationImported(entries, null), isFalse);
    expect(entries.length, 3);
    expect(entries[0]['amount'], 250.0);
  });

  test('pending bank notifications require a stable unique unreviewed key', () {
    final alerts = <dynamic>[
      {'bank': 'Т-Банк', 'key': 'a', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'bank': 'Т-Банк', 'key': 'a', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'bank': 'Т-Банк', 'key': 'b', 'title': 'Ozon Банк', 'body': 'Перевод 2 000 ₽'},
      {'bank': 'Т-Банк', 'key': 'c', 'title': 'Банк', 'body': 'Код подтверждения оплаты 500 ₽'},
      {'title': 'Банк', 'body': 'Оплата 100 ₽'},
      'malformed',
      {42: 'invalid native key'},
      {'bank': 'Т-Банк', 'key': 123, 'title': 'Т-Банк', 'body': 'Оплата 200 ₽'},
      {'bank': 'Т-Банк', 'key': '   ', 'title': 'Т-Банк', 'body': 'Оплата 300 ₽'},
      {'bank': 'Т-Банк', 'key': ' b ', 'title': 'Ozon Банк', 'body': 'Перевод 2 000 ₽'},
    ];
    expect(filterPendingBankNotifications(alerts, <String>{}).map((e) => e['key']).toList(),
      ['a', 'b']);
    expect(filterPendingBankNotifications(alerts, <String>{'a'}).map((e) => e['key']).toList(),
      ['b']);
    expect(filterPendingBankNotifications(alerts, <String>{'b'}).map((e) => e['key']).toList(),
      ['a']);
    final padded = <dynamic>[
      {'bank': 'Т-Банк', 'key': '  tx-42  ', 'title': 'Т-Банк', 'body': 'Оплата 125 ₽'},
    ];
    expect(filterPendingBankNotifications(padded, <String>{}).single['key'], 'tx-42');
    expect(filterPendingBankNotifications(padded, <String>{'tx-42'}), isEmpty);
    expect(filterPendingBankNotifications(padded, <String>{' tx-42 '}), isEmpty);
  });

  test('native bank source must be one of three explicitly supported banks', () {
    final alerts = <dynamic>[
      {'key': 't', 'bank': 'Т-Банк', 'title': 'Т-Банк', 'body': 'Оплата 100 ₽'},
      {'key': 'g', 'bank': 'Газпромбанк', 'title': 'Газпромбанк', 'body': 'Оплата 200 ₽'},
      {'key': 'o', 'bank': 'Ozon Банк', 'title': 'Ozon Банк', 'body': 'Оплата 300 ₽'},
      {'key': 'missing', 'title': 'Т-Банк', 'body': 'Оплата 400 ₽'},
      {'key': 'fake', 'bank': 'Неизвестный банк', 'title': 'Т-Банк', 'body': 'Оплата 400 ₽'},
      {'key': 'object', 'bank': {'name': 'Т-Банк'}, 'title': 'Т-Банк', 'body': 'Оплата 500 ₽'},
    ];
    expect(filterPendingBankNotifications(alerts, <String>{})
        .map((e) => e['key']).toList(), ['t', 'g', 'o']);
  });

  test('oversized or non-text native bank alerts are not imported', () {
    final valid = {'bank': 'Т-Банк', 'key': 'ok', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'};
    final alerts = <dynamic>[
      {'bank': 'Т-Банк', 'key': 'large-key-${List.filled(260, 'x').join()}',
       'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'bank': 'Т-Банк', 'key': 'line\nbreak', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'bank': 'Т-Банк', 'key': 'tab\tkey', 'title': 'Т-Банк', 'body': 'Оплата 250 ₽'},
      {'key': 'bad-title', 'title': {'bank': 'Т-Банк'},
       'body': 'Оплата 250 ₽'},
      {'bank': 'Т-Банк', 'key': 'bad-body', 'title': 'Т-Банк', 'body': ['Оплата 250 ₽']},
      {'bank': 'Т-Банк', 'key': 'long-title', 'title': List.filled(201, 'x').join(),
       'body': 'Оплата 250 ₽'},
      {'bank': 'Т-Банк', 'key': 'long-body', 'title': 'Т-Банк',
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
    expect(describeKopilkaListener({
      'lastSeen': 0, 'queued': 0, 'connected': true,
    }), contains('служба уведомлений подключена'.replaceFirst('служба', 'Служба')));
    expect(describeKopilkaListener({
      'lastSeen': 0, 'queued': 0, 'connected': false, 'lastConnected': 1234,
    }), contains('Служба отключена'));

  });

  test('diagnostics distinguish Android permission, connection and import', () {
    expect(describeKopilkaListenerPipeline(null, permissionEnabled: true),
        contains('неизвестно'));
    expect(describeKopilkaListenerPipeline({
      'permissionGranted': false, 'connected': true,
    }, permissionEnabled: true), contains('выключен'));
    expect(describeKopilkaListenerPipeline({
      'permissionGranted': true, 'connected': false,
    }, permissionEnabled: true), contains('не подключена'));
    expect(describeKopilkaListenerPipeline({
      'permissionGranted': true, 'connected': true, 'lastSeen': 0,
    }, permissionEnabled: true), contains('ещё не поступали'));
    expect(describeKopilkaListenerPipeline({
      'permissionGranted': true, 'connected': true,
      'lastSeen': 1000, 'lastAccepted': 0,
      'lastSkipped': 1100, 'lastSkipReason': 'credentials',
      'body': 'Код подтверждения 123456',
    }, permissionEnabled: true), allOf(
        contains('ни одно не прошло'), contains('кодом'),
        isNot(contains('123456'))));
    expect(describeKopilkaListenerPipeline({
      'permissionGranted': true, 'connected': true,
      'lastSeen': 1000, 'lastAccepted': 1000,
      'accepted': 3, 'lastAcceptedBank': 'Т-Банк',
      'lastSkipped': 1100, 'lastSkipReason': 'unknown secret',
      'body': 'PIN 987654',
    }, permissionEnabled: true), allOf(
        contains('Принято событий: 3'), contains('Т-Банк'),
        contains('не означает запись'), isNot(contains('987654')),
        isNot(contains('unknown secret'))));
  });

  test('per-bank listener counts are visible without notification bodies', () {
    expect(describeKopilkaBankEvents(null), contains('Android-службы'));
    final summary = describeKopilkaBankEvents({
      'bankEvents': {'Т-Банк': 4, 'Газпромбанк': 2, 'Ozon Банк': 0},
      'lastBank': 'Т-Банк',
      'body': 'Секретный код 123456',
    });
    expect(summary, contains('Т-Банк: 4'));
    expect(summary, contains('Газпромбанк: 2'));
    expect(summary, contains('Ozon Банк: 0'));
    expect(summary, isNot(contains('123456')));
    final detailed = describeKopilkaBankEvents({
      'bankEvents': {'Т-Банк': 9, 'Газпромбанк': 5, 'Ozon Банк': 2},
      'bankAccepted': {'Т-Банк': 2, 'Газпромбанк': 1, 'Ozon Банк': 0},
      'bankFiltered': {'Т-Банк': 7, 'Газпромбанк': 4, 'Ozon Банк': 2},
      'body': 'Код подтверждения 123456',
    });
    expect(detailed, contains('Т-Банк: 9 (на проверку: 2, отсеяно: 7)'));
    expect(detailed, contains('Газпромбанк: 5 (на проверку: 1, отсеяно: 4)'));
    expect(detailed, contains('Ozon Банк: 2 (на проверку: 0, отсеяно: 2)'));
    expect(detailed, isNot(contains('123456')));
    expect(describeKopilkaBankEvents({
      'bankEvents': {'Т-Банк': -5, 'Газпромбанк': 'bad'},
    }), contains('Т-Банк: 0'));
  });

  test('ambiguous bank alerts never invent a spending category', () {
    expect(suggestKopilkaCategory('Оплата 200 ₽ Магазин: Пятёрочка'), 'Продукты');
    expect(suggestKopilkaCategory('Оплата 200 ₽ Яндекс Go такси'), 'Транспорт');
    expect(suggestKopilkaCategory(
      'Оплата 200 ₽ Пятёрочка; Оплата 400 ₽ такси'), 'Другое');
    expect(suggestKopilkaCategory('Оплата 200 ₽ неизвестный магазин'), 'Другое');
  });

  test('explicit merchant labels prefill editable note without guessing', () {
    expect(suggestKopilkaMerchant('Т-Банк\nОплата 299 ₽\nМагазин: Пятёрочка'),
        'Пятёрочка');
    expect(suggestKopilkaMerchant('Ozon Банк\nMerchant: Ozon Shop'),
        'Ozon Shop');
    expect(suggestKopilkaMerchant('Газпромбанк\nТорговая точка — Аптека 36.6'),
        'Аптека 36.6');
    expect(suggestKopilkaMerchant('Оплата 300 ₽. Остаток 2000 ₽'), isNull);
    expect(suggestKopilkaMerchant('Магазин: код подтверждения 1234'), isNull);
  });

}
