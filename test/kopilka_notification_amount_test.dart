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
    ];
    expect(filterPendingBankNotifications(alerts, <String>{}).map((e) => e['key']).toList(),
      ['a', 'b']);
    expect(filterPendingBankNotifications(alerts, <String>{'a'}).map((e) => e['key']).toList(),
      ['b']);
  });

  group('Kopilka transaction notification privacy filter', () {
    test('keeps purchase, transfer and incoming money notifications', () {
      expect(isBankTransactionNotification('Т-Банк', 'Оплата 250 ₽. Остаток 5 000 ₽'), isTrue);
      expect(isBankTransactionNotification('Ozon Банк', 'Перевод 2 000 RUB'), isTrue);
      expect(isBankTransactionNotification('Газпромбанк', 'Зачисление 500 рублей'), isTrue);
    });

    test('does not offer balance-only or promotional alerts', () {
      expect(isBankTransactionNotification('Т-Банк', 'Остаток 5 000 ₽'), isFalse);
      expect(isBankTransactionNotification('Акция', 'Скидка 100 ₽'), isFalse);
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

    test('uses the nearest label when the amount precedes its action', () {
      expect(suggestNotificationAmount('250 ₽ списание. 1000 ₽ остаток'), '250');
    });

    test('allows a standalone currency amount for manual confirmation', () {
      expect(suggestNotificationAmount('1 200 RUB'), '1200');
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
    });
  });

}
