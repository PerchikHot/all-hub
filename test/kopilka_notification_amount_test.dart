import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
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
}
