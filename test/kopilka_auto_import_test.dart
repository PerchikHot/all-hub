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

  test('identical title/body payment previews import once, conflicting ones do not', () {
    final posted = alert('repeat', 'Т-Банк',
        'Оплата 250,00 руб.\\nМагазин: Пятёрочка')
      ..['title'] = 'Покупка 250 ₽';
    final entry = confidentKopilkaAutoEntry(posted, [], now);
    expect(entry?['amount'], 250.0);
    expect(entry?['note'], 'Пятёрочка');
    expect(confidentKopilkaAutoEntry(posted, [entry!], now), isNull);

    final mismatch = Map<String, dynamic>.from(posted)
      ..['body'] = 'Оплата 300 ₽\\nМагазин: Пятёрочка';
    expect(confidentKopilkaAutoEntry(mismatch, [], now), isNull);
    final twoInBody = Map<String, dynamic>.from(posted)
      ..['body'] = 'Оплата 250 ₽, комиссия 250 ₽\\nМагазин: Пятёрочка';
    expect(confidentKopilkaAutoEntry(twoInBody, [], now), isNull);
    final balance = Map<String, dynamic>.from(posted)
      ..['title'] = 'Баланс 250 ₽';
    expect(confidentKopilkaAutoEntry(balance, [], now), isNull);
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

  test('Flutter and Android agree on explicit merchants and review-only placeholders', () {
    final inline = confidentKopilkaAutoEntry(alert('inline', 'Т-Банк',
        'Покупка 250 ₽. Магазин: Пятёрочка'), [], now);
    expect(inline?['note'], 'Пятёрочка');
    final seller = confidentKopilkaAutoEntry(alert('seller', 'Т-Банк',
        'Оплата 90 ₽; Продавец: Аптека'), [], now);
    expect(seller?['note'], 'Аптека');
    for (final body in [
      'Покупка 250 ₽. Магазин: ---',
      'Payment 250 RUB. Merchant: ???',
      'Покупка 250 ₽. Магазин: Карта 1234',
      'Покупка 250 ₽ в Пятёрочке',
    ]) {
      expect(confidentKopilkaAutoEntry(
          alert('unsafe', 'Т-Банк', body), [], now), isNull, reason: body);
    }
  });

  test('pending authorization and confirmation requests never auto-post', () {
    for (final body in [
      'Подтверждение оплаты 250 ₽. Магазин: Пятёрочка',
      'Авторизация оплаты 250 ₽. Магазин: Пятёрочка',
      'Резервирование суммы 250 ₽. Магазин: Пятёрочка',
    ]) {
      expect(confidentKopilkaAutoEntry(
          alert('pending-auth', 'Т-Банк', body), [], now), isNull,
          reason: body);
    }
    expect(confidentKopilkaAutoEntry(
        alert('completed', 'Т-Банк',
            'Оплата 250 ₽. Магазин: Пятёрочка'), [], now), isNotNull);
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
  test('SQLite auto journal reconciles after permission is revoked', () {
    // Permission only controls future notification capture. Existing
    // durable SQLite payments must still reach the financial journal.
    expect(shouldReconcileStagedKopilkaEntries(
        journalHealthy: true, stagedCount: 2), isTrue);
    expect(shouldReconcileStagedKopilkaEntries(
        journalHealthy: true, stagedCount: 0), isFalse);
    expect(shouldReconcileStagedKopilkaEntries(
        journalHealthy: false, stagedCount: 2), isFalse);
  });

  test('corrupt review queue does not masquerade as empty queue', () {
    expect(decodeKopilkaReviewQueue('[]'), isEmpty);
    expect(decodeKopilkaReviewQueue('[{"key":"bank:1"}]'), hasLength(1));
    for (final raw in ['{broken', '{}', '[', 'null', '"[]"']) {
      expect(decodeKopilkaReviewQueue(raw), isNull, reason: raw);
    }
  });

  test('disconnected listener does not block durable queued transactions', () {
    expect(shouldImportQueuedKopilkaEvents(
        permissionGranted: true, journalHealthy: true, queuedCount: 3), isTrue);
    expect(shouldImportQueuedKopilkaEvents(
        permissionGranted: false, journalHealthy: true, queuedCount: 3), isFalse);
    expect(shouldImportQueuedKopilkaEvents(
        permissionGranted: true, journalHealthy: false, queuedCount: 3), isFalse);
    expect(shouldImportQueuedKopilkaEvents(
        permissionGranted: true, journalHealthy: true, queuedCount: 0), isFalse);
  });

  test('stale connected preference never implies a live listener', () {
    // A process can be killed without onListenerDisconnected being called.
    // The native channel must report its process-local connection flag.
    final stale = <String, dynamic>{
      'permissionGranted': true, 'connected': false,
      'lastConnected': DateTime(2026, 11, 1).millisecondsSinceEpoch,
      'lastSeen': 0,
    };
    expect(describeKopilkaListenerPipeline(stale, permissionEnabled: true),
        contains('служба не подключена'));
    expect(describeKopilkaListener(stale), contains('Служба отключена'));
    final live = Map<String, dynamic>.from(stale)..['connected'] = true;
    expect(describeKopilkaListenerPipeline(live, permissionEnabled: true),
        contains('Служба подключена'));
  });

  test('corrupted journal is never interpreted as an empty history', () {
    expect(decodeKopilkaJournal(null), isEmpty);
    expect(decodeKopilkaJournal('[]'), isEmpty);
    expect(decodeKopilkaJournal('[{"kind":"expense","amount":100}]'),
        hasLength(1));
    for (final raw in ['{broken', '{}', '[1]', '[null]',
        '[{"kind":"expense"}, {"x":1}, false]']) {
      expect(() => decodeKopilkaJournal(raw), throwsFormatException,
          reason: raw);
    }
  });

  test('native Android auto ledger reconciles exactly once on resume', () {
    final staged = <String, dynamic>{
      'key': 'bank:42:123', 'notificationKey': 'bank:42:123',
      'nativeClassifier': 1, 'bank': 'Т-Банк', 'kind': 'expense',
      'sourceType': 'purchase', 'amount': 250.5,
      'dateMillis': DateTime(2026, 11, 1, 13, 59).millisecondsSinceEpoch,
      'note': 'Пятёрочка',
    };
    final entry = validatedNativeKopilkaEntry(staged, [], now)!;
    expect(entry['amount'], 250.5);
    expect(entry['kind'], 'expense');
    expect(entry['autoImported'], isTrue);
    expect(entry['notificationKey'], 'bank:42:123');
    expect(validatedNativeKopilkaEntry(staged, [entry], now), isNull);
  });

  test('native ledger rejects forged, ambiguous or duplicate postings', () {
    final candidate = <String, dynamic>{
      'key': 'n-1', 'nativeClassifier': 1, 'bank': 'Газпромбанк',
      'kind': 'income', 'sourceType': 'salary', 'amount': 20000.0,
      'dateMillis': DateTime(2026, 11, 1, 13, 59).millisecondsSinceEpoch,
      'note': 'Зарплата',
    };
    expect(validatedNativeKopilkaEntry(candidate, [], now), isNotNull);
    for (final bad in [
      {'nativeClassifier': 0},
      {'bank': 'Unknown'},
      {'amount': -5},
      {'amount': double.infinity},
      {'dateMillis': 0},
      {'sourceType': 'transfer'},
      {'kind': 'expense'},
      {'note': 'Подмена\nданных'},
    ]) {
      expect(validatedNativeKopilkaEntry({...candidate, ...bad}, [], now),
          isNull, reason: bad.toString());
    }
    final otherBank = [{
      'kind': 'expense', 'bank': 'Т-Банк', 'amount': 20000.0,
      'date': DateTime(2026, 11, 1, 13, 58).toIso8601String(),
    }];
    expect(validatedNativeKopilkaEntry(candidate, otherBank, now), isNull);
  });

  test('diagnostics show native staging without raw bank messages', () {
    final message = describeKopilkaListener({
      'connected': true, 'lastSeen': 0, 'nativeAutoStaged': 2,
      'nativeJournalPending': 2,
      'nativeStageError': 'ledger_full',
      'nativeAutoStagedTotal': 4, 'nativeReviewOnlyTotal': 9,
    });
    expect(message, contains('Сохранено Android без запуска Flutter, ожидает сверки: 2'));
    expect(message, contains('нативный журнал заполнен'));
    expect(message, contains('В автономном SQLite-журнале: 2'));
    expect(message, contains('подготовлено автоматически 4'));
    expect(message, contains('оставлено на проверку 9'));
    expect(message, isNot(contains('Пятёрочка')));
  });

  test('reconnect recovery is reported without notification contents', () {
    final message = describeKopilkaListener({
      'connected': true,
      'lastSeen': 0,
      'lastRecoveryScan': DateTime(2026, 11, 1).millisecondsSinceEpoch,
      'recoveryCandidates': 3,
      'queued': 2,
      'queueCapacity': 500,
      'queueRemaining': 498,
    });
    expect(message, contains('проверено активных банковских уведомлений: 3'));
    expect(message, contains('восстановить не может'));
    expect(message, isNot(contains('код подтверждения')));
  });


  test('only previously saved or reviewed keys are acknowledged on resume', () {
    final raw = <dynamic>[
      {'key': 'saved', 'bank': 'Т-Банк'},
      {'key': 'new', 'bank': 'Ozon Банк'},
      {'key': 'saved', 'bank': 'Т-Банк'},
      {'key': 12},
      {'key': '  dismissed  '},
    ];
    expect(kopilkaQueuedAcknowledgements(raw, {'saved', 'dismissed'}),
        ['saved', 'dismissed']);
    expect(kopilkaQueuedAcknowledgements(raw, {}), isEmpty);
  });


}
