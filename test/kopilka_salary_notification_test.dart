import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/kopilka_page.dart';

void main() {
  test('salary-only bank notification is eligible for review as income', () {
    const title = 'Зарплата';
    const body = '20 260 ₽ за октябрь';
    expect(isBankTransactionNotification(title, body), isTrue);
    expect(suggestNotificationAmount('$title\n$body'), '20260');
    expect(suggestNotificationKind('$title\n$body'), 'income');
    expect(kopilkaPendingReviewPreview({'title': title, 'body': body}),
        contains('Возможный доход'));
  });

  test('English payroll alert is treated as income, never as a purchase', () {
    expect(isBankTransactionNotification('Payroll', 'Salary 20260 RUB'), isTrue);
    expect(suggestNotificationKind('Payroll Salary 20260 RUB'), 'income');
  });

  test('salary confirmation codes and future payments are excluded', () {
    expect(isBankTransactionNotification('Зарплата',
        'Код подтверждения 1234. Зачисление 20 260 ₽'), isFalse);
    expect(isBankTransactionNotification('Зарплата',
        'Зарплата 20 260 ₽ будет зачислена завтра'), isFalse);
  });
}
