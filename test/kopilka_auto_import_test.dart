import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  final now = DateTime(2026, 11, 1, 14);
  Map<String, dynamic> alert(String key, String bank, String body) => {
    'key': key, 'bank': bank, 'title': bank, 'body': body,
    'time': DateTime(2026, 11, 1, 13, 59).millisecondsSinceEpoch,
  };

  test('posts a single completed merchant purchase with a stable ID', () {
    final event = alert('t-1', 'Т-Банк',
        'Покупка 250,50 ₽\nМагазин: Пятёрочка');
    final entry = confidentKopilkaAutoEntry(event, [], now)!;
    expect(entry['kind'], 'expense');
    expect(entry['amount'], 250.50);
    expect(entry['bank'], 'Т-Банк');
    expect(entry['category'], 'Продукты');
    expect(entry['notificationKey'], 't-1');
    expect(entry['autoImported'], isTrue);
    expect(confidentKopilkaAutoEntry(event, [entry], now), isNull);
  });

  test('accepts explicit salary and completed purchase refund as income', () {
    final salary = confidentKopilkaAutoEntry(
        alert('g-1', 'Газпромбанк', 'Зарплата поступила 20 000 ₽'), [], now);
    expect(salary?['kind'], 'income');
    expect(salary?['amount'], 20000.0);
    final refund = confidentKopilkaAutoEntry(
        alert('o-1', 'Ozon Банк', 'Возврат покупки 350 ₽'), [], now);
    expect(refund?['kind'], 'income');
    expect(refund?['amount'], 350.0);
  });

  test('ambiguous amounts, OTP, transfers and generic debits remain review-only', () {
    for (final body in [
      'Покупка 250 ₽. Остаток 4 000 ₽\nМагазин: Пятёрочка',
      'Покупка 250 ₽. Покупка 300 ₽\nМагазин: Пятёрочка',
      'Перевод 250 ₽\nМагазин: Пятёрочка',
      'Списано 250 ₽',
      'Оплата 250 ₽',
      'Код подтверждения оплаты 250 ₽: 1234',
      'Покупка 250 ₽ не прошла\nМагазин: Пятёрочка',
    ]) {
      expect(confidentKopilkaAutoEntry(
          alert('review', 'Т-Банк', body), [], now), isNull,
          reason: body);
    }
  });

  test('same-value duplicate and possible own-account transfer are not auto-posted', () {
    final event = alert('t-2', 'Т-Банк',
        'Покупка 250 ₽\nМагазин: Пятёрочка');
    final sameBank = [{
      'kind': 'expense', 'bank': 'Т-Банк', 'amount': 250.0,
      'date': DateTime(2026, 11, 1, 13, 58).toIso8601String(),
    }];
    expect(confidentKopilkaAutoEntry(event, sameBank, now), isNull);
    final otherBank = [{
      'kind': 'income', 'bank': 'Ozon Банк', 'amount': 250.0,
      'date': DateTime(2026, 11, 1, 13, 58).toIso8601String(),
    }];
    expect(confidentKopilkaAutoEntry(event, otherBank, now), isNull);
  });
}
