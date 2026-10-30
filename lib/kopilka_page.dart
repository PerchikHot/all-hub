import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Suggests an amount for manual review. Balance-only notifications must
/// not be prefilled as expenses; the user still confirms every operation.
String suggestNotificationAmount(String body) {
  final amountPattern = RegExp(
    r'(\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,](\d{1,2}))?\s*(?:₽|руб(?:\.|ль|ля|лей)?|RUB)',
    caseSensitive: false,
  );
  final transactionWords = RegExp(
    r'покупк|оплат|списан|перевод|пополнен|зачислен|поступил|сняти|возврат|выдан|purchase|payment|transfer|refund',
    caseSensitive: false,
  );
  final balanceWords = RegExp(
    r'остаток|доступно|баланс|available|balance',
    caseSensitive: false,
  );
  final matches = amountPattern.allMatches(body).toList();
  String result = '';
  var bestScore = -1;
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final beforeStart = i == 0
        ? (match.start > 80 ? match.start - 80 : 0)
        : matches[i - 1].end;
    final afterEnd = i + 1 < matches.length
        ? matches[i + 1].start
        : (match.end + 60 < body.length ? match.end + 60 : body.length);
    final before = body.substring(beforeStart, match.start)
        .split(RegExp(r'[\n;]|[.!?]\s+')).last;
    final after = body.substring(match.end, afterEnd)
        .split(RegExp(r'[\n;]|[.!?]\s+')).first;
    final beforeTransaction = transactionWords.hasMatch(before);
    final beforeBalance = balanceWords.hasMatch(before);
    final afterTransaction = transactionWords.hasMatch(after);
    final afterBalance = balanceWords.hasMatch(after);
    // The nearest transaction/balance label takes precedence.
    if (beforeBalance && !beforeTransaction) continue;
    if (!beforeTransaction && afterBalance && !afterTransaction) continue;
    final score = beforeTransaction ? 10 : afterTransaction ? 5 : 0;
    if (score > bestScore) {
      final whole = match.group(1)!.replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
      final decimals = match.group(2);
      final candidate = decimals == null ? whole : '$whole.$decimals';
      // Zero-value bank alerts are not transactions. Ignore them rather
      // than prefill an invalid amount or hide a later valid purchase.
      final numeric = double.tryParse(candidate);
      if (numeric == null || !numeric.isFinite || numeric <= 0) continue;
      bestScore = score;
      result = candidate;
    }
  }
  return result;
}

/// Conservative default for the review dialog, never an automatic posting.
/// Ambiguous transfers and notifications mentioning both directions remain
/// expenses until the user explicitly selects another operation type.
String suggestNotificationKind(String text) {
  final incoming = RegExp(
    r'поступлен|поступил|зачислен|пополнен|пополнение|возврат|кэшбэк|кешбэк|refund|credited|deposit',
    caseSensitive: false,
  );
  final outgoing = RegExp(
    r'списан|списание|покупк|оплат|перевод|сняти|withdraw|payment|purchase|debited',
    caseSensitive: false,
  );
  return incoming.hasMatch(text) && !outgoing.hasMatch(text)
      ? 'income'
      : 'expense';
}

/// Keep login codes, promotions and balance-only bank alerts out of the
/// transaction review screen. The native Android listener applies the same
/// conservative gate before persisting new notifications.
bool isBankTransactionNotification(String title, String body) {
  final text = '$title\n$body';
  final transaction = RegExp(
    r'покупк|оплат|списан|перевод|поступ|зачисл|пополн|возврат|кэшбэк|кешбэк|сняти|выдач|purchase|payment|transfer|refund|credited|deposit|withdraw',
    caseSensitive: false,
  );
  final currency = RegExp(
    r'₽|руб(?:\.|ль|ля|лей)?|\bRUB\b',
    caseSensitive: false,
  );
  final sensitive = RegExp(
    r'код\s+(?:подтверждения|входа|для\s+(?:входа|подтверждения)|операции|из\s+смс)|код\s*[:№]|(?:ваш|your)\s+(?:код|code)|(?:sms|смс)[-\s]*код|одноразов(?:ый|ого)\s+код|никому\s+не\s+сообщайте|verification\s+code|one[- ]time\s+(?:password|code)|\bOTP\b',
    caseSensitive: false,
  );
  // Password/PIN/CVV alerts can contain a payment amount but must never
  // appear in the transaction-import review list.
  final credentialWords = RegExp(
    r'парол[ья]|password|passcode|\bpin\b|\bcvv\b|\bcvc\b|код\s+безопасности',
    caseSensitive: false,
  );
  // A declined, cancelled, failed or still pending payment is not a completed expense.
  // Keep these alerts out of manual import suggestions; never delete them
  // from the Android notification tray or change saved transactions.
  final failedTransaction = RegExp(
    r'отклон[её]н|не\s+(?:выполнен|прошл[ао]|удал(?:ось|ась))|неуспешн|отмен[её]н|недостаточн[а-яё]*\s+средств|ожида[её]т\s+подтверждени|в\s+обработк|declined|rejected|failed|cancelled|canceled|pending|processing|awaiting\s+approval|отказан[а-яё]*|не\s+одобрен[а-яё]*|ошибка\s+(?:оплаты|перевода)|insufficient\s+funds|требует\s+подтверждени[яй]|подтвердите\s+(?:операцию|плат[её]ж|перевод|оплату)|requires\s+confirmation|authorization\s+required|заблокирован[а-яё]*|приостановлен[а-яё]*|заморожен[а-яё]*|\bblocked\b|\bsuspended\b|\bon\s+hold\b',
    caseSensitive: false,
  );
  // Some banks report an unposted operation without using the words
  // "declined" or "pending". Keep these out of completed transaction review.
  final notCompleted = RegExp(
    r'не\s+(?:провед[её]н[а-яё]*|подтвержд[её]н[а-яё]*|заверш[её]н[а-яё]*|состоял[а-яё]*)|\bnot\s+(?:completed|processed|approved|confirmed)\b',
    caseSensitive: false,
  );
  // Future-dated payment reminders are not evidence of a posted expense.
  // Do not suggest them for import even if they contain an exact amount.
  final scheduledTransaction = RegExp(
    r'запланирован[а-яё]*|планиру[ею]тся|будет\s+(?:списан[а-яё]*|списано|оплачен[а-яё]*|провед[её]н[а-яё]*|оплата)|ожидается\s+(?:завтра|послезавтра)|\bwill\s+be\s+(?:charged|debited|paid)\b|\b(?:scheduled|upcoming)\b',
    caseSensitive: false,
  );
  // A currency label without a readable amount is not a transaction.
  return transaction.hasMatch(text) &&
      currency.hasMatch(text) &&
      suggestNotificationAmount(text).isNotEmpty &&
      !sensitive.hasMatch(text) && !credentialWords.hasMatch(text) &&
      !failedTransaction.hasMatch(text) && !notCompleted.hasMatch(text) &&
      !scheduledTransaction.hasMatch(text);
}

/// Only review a native notification once, even if the listener returns the
/// same event repeatedly. Events without a stable key cannot be safely imported.
List<Map<String, dynamic>> filterPendingBankNotifications(
  List<dynamic> raw, Set<String> reviewed,
) {
  final seen = <String>{};
  // Historical keys may contain padding; compare their normalized form
  // without rewriting any existing saved operation.
  final normalizedReviewed = reviewed.map((key) => key.trim()).toSet();
  return raw.whereType<Map>()
      // A single malformed native event must not hide valid bank alerts.
      .where((e) => e.keys.every((key) => key is String))
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) {
        // Native notification IDs must be stable strings, not arbitrary
        // JSON values that stringify to a misleading deduplication key.
        final rawKey = e['key'];
        if (rawKey is! String) return false;
        final key = rawKey.trim();
        if (key.isEmpty || key.length > 256 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(key) ||
            normalizedReviewed.contains(key)) {
          return false;
        }
        // Reject malformed or oversized native payloads before parsing.
        // Never stringify arbitrary objects into a financial notification.
        final title = e['title'];
        final body = e['body'];
        if (title is! String || body is! String ||
            title.length > 200 || body.length > 2048) {
          return false;
        }
        if (!isBankTransactionNotification(title, body)) {
          return false;
        }
        if (!seen.add(key)) return false;
        // Store the canonical ID so later refreshes cannot re-import it.
        e['key'] = key;
        return true;
      }).toList();
}


/// Prevent duplicate financial postings when two review dialogs are open or
/// a native notification is delivered again before its key is archived.
/// This reads only saved operation IDs; it never changes existing entries.
bool isKopilkaNotificationImported(
  Iterable<Map<String, dynamic>> entries, String? notificationKey,
) {
  final key = notificationKey?.trim() ?? '';
  if (key.isEmpty) return false;
  return entries.any((entry) {
    final stored = entry['notificationKey'];
    return stored is String && stored.trim() == key;
  });
}

/// Invalid legacy amounts must never crash totals or contaminate balances.
double safeKopilkaAmount(Map<String, dynamic> entry) {
  final value = entry['amount'];
  // Saved amounts are magnitudes. A negative legacy value must not reverse
  // the meaning of an expense or income in the displayed totals.
  return value is num && value.isFinite && value >= 0
      ? value.toDouble() : 0.0;
}

/// Net change of the visible history. Internal transfers are not income.
/// This is display-only and never rewrites stored transactions.
double kopilkaNetChange(Iterable<Map<String, dynamic>> visible) {
  var net = 0.0;
  for (final entry in visible) {
    final amount = safeKopilkaAmount(entry);
    if (entry['kind'] == 'income') { net += amount; }
    if (entry['kind'] == 'expense') { net -= amount; }
  }
  return net;
}

/// Count own-account transfers that need account assignment. Display-only:
/// never changes the saved operations or counts transfers as income.
int countIncompleteKopilkaTransfers(Iterable<Map<String, dynamic>> entries) {
  return entries.where((entry) {
    if (entry['kind'] != 'transfer') return false;
    final source = (entry['from'] ?? '').toString().trim();
    final destination = (entry['to'] ?? '').toString().trim();
    return source.isEmpty || destination.isEmpty;
  }).length;
}

/// Parse manually entered amounts without silently accepting broken grouping.
/// This does not change any historical transaction values.
double? parseKopilkaAmount(String input) {
  final value = input.trim().replaceFirst(
    RegExp(r'\s*(?:₽|руб(?:\.|ль|ля|лей)?|RUB)$', caseSensitive: false), '',
  ).trim();
  final plain = RegExp(r'^\d+(?:[.,]\d{1,2})?$');
  final grouped = RegExp(r'^\d{1,3}(?:[ \u00a0\u202f]\d{3})+(?:[.,]\d{1,2})?$');
  if (!plain.hasMatch(value) && !grouped.hasMatch(value)) return null;
  final normalized = value.replaceAll(RegExp(r'[ \u00a0\u202f]'), '').replaceAll(',', '.');
  final amount = double.tryParse(normalized);
  return amount != null && amount.isFinite && amount > 0 ? amount : null;
}

/// Canonicalize only whole known bank labels for the advisory self-transfer
/// filter. Never collapse arbitrary account names: two different cards at
/// the same bank must not be silently treated as one saved account.
String canonicalKopilkaAccountLabel(String value) {
  final label = value.trim().toLowerCase().replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ');
  const aliases = <String, String>{
    'тинькофф': 'т-банк',
    'тбанк': 'т-банк',
    'т банк': 'т-банк',
    'ozon': 'ozon банк',
    'ozon bank': 'ozon банк',
    'озон': 'ozon банк',
    'озон банк': 'ozon банк',
    'газпром': 'газпромбанк',
    'gazprombank': 'газпромбанк',
    'cash': 'наличные',
    'нал': 'наличные',
  };
  return aliases[label] ?? label;
}

/// Local search of already saved transactions; never sends finance data online.
bool matchesKopilkaHistory(Map<String, dynamic> entry, String query) {
  // Normalize Russian thousands separators and decimal commas for searching.
  // The saved transaction itself is never modified.
  final normalizedQuery = query.toLowerCase().trim().replaceAll('ё', 'е')
      // Let users search ISO-stored dates as DD.MM.YYYY without changing data.
      .replaceAllMapped(
        RegExp(r'\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b'),
        (match) => '${match.group(3)}-${match.group(2)!.padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}',
      )
      .replaceAllMapped(
        RegExp(r'\d{1,3}(?:[ \u00a0\u202f]\d{3})+(?:[.,]\d{1,2})?'),
        (match) => match.group(0)!.replaceAll(
          RegExp(r'[ \u00a0\u202f]'), '',
        ),
      )
      .replaceAllMapped(
        RegExp(r'(\d+),(\d{1,2})(?!\d)'),
        (match) => '${match.group(1)}.${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'\d+\.\d{1,2}(?!\d)'),
        (match) => double.tryParse(match.group(0)!)?.toString() ??
            match.group(0)!,
      )
      // Ignore currency labels only when they follow a numeric amount.
      .replaceAllMapped(
        RegExp(r'(\d)\s*(?:₽|руб(?:\.|ль|ля|лей)?|rub)(?=\s|$)', caseSensitive: false),
        (match) => match.group(1)!,
      );
  // Match common Russian bank names without rewriting the saved operation.
  // Aliases apply to complete search words only, not substrings of notes.
  final words = normalizedQuery.split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final text = [
    entry['note'], entry['bank'], entry['from'], entry['to'],
    entry['date'], entry['kind'], entry['amount'],
    entry['kind'] == 'income' ? 'доход поступление' :
      entry['kind'] == 'expense' ? 'расход покупка' : 'перевод',
  ].map((value) => (value ?? '').toString().toLowerCase().replaceAll('ё', 'е')).join(' ');
  // Bank rebrands and transliterations must work in both directions:
  // a saved legacy 'Тинькофф' entry should match 'Т-Банк' and vice versa.
  return words.every((word) {
    // date:/дата: matches the saved day, never a date in a note.
    // The query normalization above also supports DD.MM.YYYY.
    if (word.startsWith('date:') || word.startsWith('дата:')) {
      final requested = word.substring(word.indexOf(':') + 1);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(requested)) {
        return false;
      }
      final parsed = DateTime.tryParse(requested);
      if (parsed == null ||
          parsed.toIso8601String().substring(0, 10) != requested) {
        return false;
      }
      final saved = (entry['date'] ?? '').toString();
      return saved.length >= 10 && saved.substring(0, 10) == requested;
    }
    // Inclusive date range filters compare the saved transaction day only.
    // Reject impossible dates and missing/invalid saved dates; never infer
    // dates from a note. ISO days compare lexicographically in calendar order.
    if (word.startsWith('since:') || word.startsWith('until:') ||
        word.startsWith('с:') || word.startsWith('по:')) {
      final isStart = word.startsWith('since:') || word.startsWith('с:');
      final requested = word.substring(word.indexOf(':') + 1);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(requested)) {
        return false;
      }
      final parsed = DateTime.tryParse(requested);
      if (parsed == null ||
          parsed.toIso8601String().substring(0, 10) != requested) {
        return false;
      }
      final saved = (entry['date'] ?? '').toString();
      if (saved.length < 10) {
        return false;
      }
      final day = saved.substring(0, 10);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
        return false;
      }
      final savedDate = DateTime.tryParse(day);
      if (savedDate == null ||
          savedDate.toIso8601String().substring(0, 10) != day) {
        return false;
      }
      return isStart ? day.compareTo(requested) >= 0
          : day.compareTo(requested) <= 0;
    }
    // Find operations needing a description without changing saved entries.
    // Unknown has: values fail closed rather than matching arbitrary notes.
    if (word.startsWith('has:') || word.startsWith('есть:')) {
      final requested = word.substring(word.indexOf(':') + 1);
      final hasNote = (entry['note'] ?? '').toString().trim().isNotEmpty;
      if (requested == 'note' || requested == 'заметка') return hasNote;
      if (requested == 'no-note' || requested == 'без-заметки') return !hasNote;
      // Find legacy records with missing or malformed calendar dates locally.
      // Do not repair or rewrite a transaction without user confirmation.
      if (requested == 'date' || requested == 'no-date') {
        final saved = (entry['date'] ?? '').toString();
        final day = saved.length >= 10 ? saved.substring(0, 10) : '';
        final parsed = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)
            ? DateTime.tryParse(day) : null;
        final valid = parsed != null &&
            parsed.toIso8601String().substring(0, 10) == day;
        return requested == 'date' ? valid : !valid;
      }
      if (requested == 'amount' || requested == 'no-amount') {
        // Legacy imports may lack a usable amount. Never rewrite them.
        // Zero is valid for reconciliation; negative and non-finite values
        // are not valid transaction amounts in the current data model.
        final value = entry['amount'];
        final hasAmount = value is num && value.isFinite && value >= 0;
        return requested == 'amount' ? hasAmount : !hasAmount;
      }
      // Find incomplete own-account transfers without confusing an ordinary
      // purchase with a transfer that has a missing source/destination.
      if (requested == 'from' || requested == 'no-from' ||
          requested == 'to' || requested == 'no-to') {
        if (entry['kind'] != 'transfer') return false;
        final source = requested == 'from' || requested == 'no-from';
        final account = (entry[source ? 'from' : 'to'] ?? '').toString().trim();
        final exists = account.isNotEmpty;
        return requested.startsWith('no-') ? !exists : exists;
      }
      // Flag transfers accidentally assigned to the same account.
      // Both account fields must be present; incomplete transfers are
      // covered separately by has:no-from and has:no-to.
      if (requested == 'same-account' || requested == 'different-accounts') {
        if (entry['kind'] != 'transfer') return false;
        final source = canonicalKopilkaAccountLabel(
            (entry['from'] ?? '').toString());
        final destination = canonicalKopilkaAccountLabel(
            (entry['to'] ?? '').toString());
        if (source.isEmpty || destination.isEmpty) return false;
        return requested == 'same-account'
            ? source == destination : source != destination;
      }
      if (requested == 'bank' || requested == 'no-bank') {
        // Transfers have source/destination accounts; other operations use bank.
        // Do not mistake a bank mentioned in the note for an assigned account.
        final fields = entry['kind'] == 'transfer'
            ? [entry['from'], entry['to']]
            : [entry['bank']];
        final hasBank = fields.any((value) =>
            (value ?? '').toString().trim().isNotEmpty);
        return requested == 'bank' ? hasBank : !hasBank;
      }
      return false;
    }
    // note:/заметка: searches only the user's description, not account names,
    // dates or other fields. All matching remains local to this device.
    if (word.startsWith('note:') || word.startsWith('заметка:')) {
      final requested = word.substring(word.indexOf(':') + 1);
      if (requested.isEmpty) return false;
      final note = (entry['note'] ?? '').toString()
          .toLowerCase().replaceAll('ё', 'е');
      return note.contains(requested);
    }
    // Structured transaction-type filter: notes mentioning a transfer must
    // not make an ordinary expense appear in the transfers list.
    if (word.startsWith('type:') || word.startsWith('тип:')) {
      final requested = word.substring(word.indexOf(':') + 1);
      const aliases = <String, String>{
        'income': 'income', 'доход': 'income',
        'expense': 'expense', 'расход': 'expense',
        'transfer': 'transfer', 'перевод': 'transfer',
      };
      final expected = aliases[requested];
      return expected != null && entry['kind'] == expected;
    }
    // Inspect the direction of an own-account transfer, not words in notes.
    // This is a local-only filter and never alters either account.
    if (word.startsWith('from:') || word.startsWith('to:') ||
        word.startsWith('откуда:') || word.startsWith('куда:')) {
      if (entry['kind'] != 'transfer') return false;
      final key = word.substring(0, word.indexOf(':'));
      final requested = word.substring(word.indexOf(':') + 1);
      if (requested.isEmpty) return false;
      final source = key == 'from' || key == 'откуда';
      final account = (entry[source ? 'from' : 'to'] ?? '').toString()
          .toLowerCase().replaceAll('ё', 'е');
      return account.contains(requested);
    }
    // bank:/банк: limits the search to real account fields, never notes.
    // Transfers match either source or destination account.
    if (word.startsWith('bank:') || word.startsWith('банк:')) {
      final requested = word.substring(word.indexOf(':') + 1);
      if (requested.isEmpty) return false;
      final accounts = [entry['bank'], entry['from'], entry['to']]
          .map((value) => (value ?? '').toString().toLowerCase()
              .replaceAll('ё', 'е')).join(' ');
      const aliases = <String, List<String>>{
        'ozon': ['ozon', 'озон'],
        'озон': ['ozon', 'озон'],
        'тинькофф': ['тинькофф', 'т-банк', 'тбанк'],
        'т-банк': ['тинькофф', 'т-банк', 'тбанк'],
        'тбанк': ['тинькофф', 'т-банк', 'тбанк'],
        'газпром': ['газпромбанк', 'gazprombank'],
        'газпромбанк': ['газпромбанк', 'gazprombank'],
        'gazprombank': ['газпромбанк', 'gazprombank'],
        'нал': ['наличные', 'cash'],
        'cash': ['наличные', 'cash'],
      };
      final candidates = aliases[requested] ?? [requested];
      return candidates.any((candidate) => accounts.contains(candidate));
    }
    // min:/max: filter by the saved amount, not by numbers in a note.
    // Use kopecks to avoid floating point comparison surprises.
    if (word.startsWith('min:') || word.startsWith('max:')) {
      final isMinimum = word.startsWith('min:');
      final raw = word.substring(4);
      if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) {
        return false;
      }
      final limit = double.tryParse(raw);
      final amount = entry['amount'];
      if (limit == null || !limit.isFinite || amount is! num ||
          !amount.isFinite || amount < 0) {
        return false;
      }
      final cents = (amount.toDouble() * 100).round();
      final boundary = (limit * 100).round();
      return isMinimum ? cents >= boundary : cents <= boundary;
    }
    // sum: compares saved kopecks, never a number inside a note or date.
    if (word.startsWith('sum:')) {
      final raw = word.substring(4);
      if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) {
        return false;
      }
      final wanted = double.tryParse(raw);
      if (wanted == null || !wanted.isFinite || wanted <= 0) {
        return false;
      }
      final amount = entry['amount'];
      return amount is num && amount.isFinite &&
          (amount.toDouble() * 100).round() == (wanted * 100).round();
    }
    if (word == 'озон' || word == 'ozon') {
      return text.contains('ozon') || text.contains('озон');
    }
    if (word == 'тинькофф' || word == 'т-банк' || word == 'тбанк') {
      return text.contains('тинькофф') || text.contains('т-банк') ||
          text.contains('тбанк');
    }
    if (word == 'нал' || word == 'cash') {
      // Match only account fields: a note mentioning cash is not a cash account.
      final accounts = [entry['bank'], entry['from'], entry['to']]
          .map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return accounts.contains('наличные') || accounts.contains('cash');
    }
    if (word == 'газпром' || word == 'газпромбанк' || word == 'gazprombank') {
      return text.contains('газпромбанк') || text.contains('gazprombank');
    }
    // A leading minus excludes a matching word from the local history.
    // This can be combined with date, bank and amount filters, e.g.
    // "тип:расход -такси". A lone minus is an invalid filter.
    if (word.startsWith('-')) {
      return word.length > 1 && !text.contains(word.substring(1));
    }
    return text.contains(word);
  });
}

/// Local-first finance notebook. No bank credentials or transactions leave the device.
/// Human-readable listener health without exposing notification bodies.
String describeKopilkaListener(Map<String, dynamic>? diagnostics) {
  if (diagnostics == null) return 'Диагностика доступна в отдельной Android APK Копилки.';
  final lastSeen = diagnostics['lastSeen'];
  final queued = diagnostics['queued'];
  final connected = diagnostics['connected'] == true;
  final lastConnected = diagnostics['lastConnected'];
  final connection = connected
      ? 'Служба уведомлений подключена.'
      : lastConnected is int && lastConnected > 0
          ? 'Служба отключена — проверь разрешение и энергосбережение.'
          : 'Подключение службы ещё не подтверждено.';
  if (lastSeen is! int || lastSeen <= 0) {
    return '$connection Уведомлений от поддерживаемых банков ещё не получено. Открой банковское приложение и проверь доступ.';
  }
  final bank = (diagnostics['lastBank'] ?? '').toString();
  final time = DateTime.fromMillisecondsSinceEpoch(lastSeen).toLocal();
  final stamp = '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  return '$connection Последнее уведомление: ${bank.isEmpty ? 'банк' : bank}, $stamp · в очереди: ${queued is int && queued >= 0 ? queued : 0}.';
}

/// Counts supported-bank events observed by the native listener, including
/// rejected OTP/balance alerts. No message bodies are included in diagnostics.
/// Zero can also mean that a bank changed its Android package identifier.
String describeKopilkaBankEvents(Map<String, dynamic>? diagnostics) {
  final raw = diagnostics?['bankEvents'];
  if (raw is! Map) return 'По каждому банку: данные появятся после подключения Android-службы.';
  const banks = ['Т-Банк', 'Газпромбанк', 'Ozon Банк'];
  final counts = banks.map((bank) {
    final value = raw[bank];
    final count = value is int && value >= 0 ? value : 0;
    return '$bank: $count';
  }).join(' · ');
  return 'События по банкам (без текста): $counts. Ноль — проверь разрешение, энергосбережение и версию банковского приложения.';
}

/// Categories are chosen explicitly during confirmation, never inferred from
/// private bank notification text. Older entries stay in "Без категории".
const kopilkaExpenseCategories = <String>[
  'Продукты', 'Транспорт', 'Жильё', 'Связь', 'Здоровье',
  'Развлечения', 'Покупки', 'Другое',
];

String kopilkaExpenseCategory(Map<String, dynamic> entry) {
  final category = entry['category'];
  return category is String && kopilkaExpenseCategories.contains(category)
      ? category : 'Без категории';
}

/// Read-only analytics: transfers and income never inflate expense totals.
Map<String, double> summarizeKopilkaExpenses(
    Iterable<Map<String, dynamic>> transactions) {
  final totals = <String, double>{};
  for (final entry in transactions) {
    if (entry['kind'] != 'expense') continue;
    final amount = safeKopilkaAmount(entry);
    if (!amount.isFinite || amount <= 0) continue;
    final category = kopilkaExpenseCategory(entry);
    totals.update(category, (old) => old + amount, ifAbsent: () => amount);
  }
  return totals;
}

class KopilkaPage extends StatefulWidget {
  const KopilkaPage({super.key});
  @override
  State<KopilkaPage> createState() => _KopilkaPageState();
}

class _KopilkaPageState extends State<KopilkaPage> with WidgetsBindingObserver {
  final entries = <Map<String, dynamic>>[];
  bool loading = true;
  String historyQuery = '';
  final historySearchController = TextEditingController();
  static const _notifications = MethodChannel('kopilka/notifications');
  bool notificationsEnabled = false;
  Map<String, dynamic>? listenerDiagnostics;
  final pendingNotifications = <Map<String, dynamic>>[];
  int visiblePendingCount = 10;
  double goal = 100000;
  final banks = const ['Т-Банк', 'Газпромбанк', 'Ozon Банк', 'Наличные'];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load persisted entries before filtering already imported notifications.
    _load().then((_) { if (mounted) _refreshNotifications(); });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    historySearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString('kopilka_entries_v1') ?? '[]') as List;
      entries.addAll(saved.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {}
    if (!mounted) return;
    // Legacy or corrupted goal values must not freeze the dashboard.
    // Preserve stored data; use a safe display fallback instead.
    final storedGoal = prefs.get('kopilka_goal_v1');
    final safeGoal = storedGoal is num && storedGoal.isFinite && storedGoal > 0
        ? storedGoal.toDouble() : 100000.0;
    setState(() { goal = safeGoal; loading = false; });
  }

  Future<void> _refreshNotifications() async {
    try {
      final enabled = await _notifications.invokeMethod<bool>('enabled') ?? false;
      final raw = await _notifications.invokeMethod<String>('pending') ?? '[]';
      final nativeDiagnostics = await _notifications.invokeMethod<Map<dynamic, dynamic>>('diagnostics');
      final diagnostics = nativeDiagnostics?.map(
        (key, value) => MapEntry(key.toString(), value));
      final prefs = await SharedPreferences.getInstance();
      final reviewed = (prefs.getStringList('kopilka_reviewed_notifications_v1') ?? <String>[]).toSet();
      // Also check saved operations: a crash after saving an operation but
      // before recording the reviewed key must not cause a second import.
      reviewed.addAll(entries.map((e) => (e['notificationKey'] ?? '').toString())
          .where((key) => key.isNotEmpty));
      final data = filterPendingBankNotifications(jsonDecode(raw) as List, reviewed);
      if (mounted) {
        setState(() {
          notificationsEnabled = enabled;
          listenerDiagnostics = diagnostics;
          pendingNotifications..clear()..addAll(data);
        });
      }
    } on MissingPluginException {
      // Embedded All Hub builds do not include the standalone listener yet.
    } on PlatformException {
      // Android settings may be unavailable on some devices.
    } on FormatException {
      // Malformed notification data must not crash the finance dashboard.
    } on TypeError {
      // Older native queue formats may not match the current schema.
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _notifications.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Установи отдельную APK Копилки для подключения уведомлений.')));
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть настройки уведомлений.')));
      }
    }
  }

  // A reviewed or dismissed alert is removed individually from the native
  // queue. Never clear other pending alerts or create an operation silently.
  Future<void> _archiveNotificationKey(String key) async {
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final reviewed = prefs.getStringList('kopilka_reviewed_notifications_v1') ?? <String>[];
    reviewed.remove(key);
    reviewed.add(key);
    if (reviewed.length > 500) reviewed.removeRange(0, reviewed.length - 500);
    await prefs.setStringList('kopilka_reviewed_notifications_v1', reviewed);
    try {
      await _notifications.invokeMethod<void>('dismiss', {'key': key});
    } on MissingPluginException {
      // All Hub embeds the finance page without the standalone listener.
    } on PlatformException {
      // The local reviewed key still prevents a duplicate suggestion.
    }
    if (mounted) {
      setState(() => pendingNotifications.removeWhere((e) => e['key'] == key));
    }
  }

  Future<void> _reviewNotification(Map<String, dynamic> event) async {
    final key = (event['key'] ?? '').toString().trim();
    if (isKopilkaNotificationImported(entries, key)) {
      await _archiveNotificationKey(key);
      return;
    }
    final title = (event['title'] ?? '').toString();
    final body = (event['body'] ?? '').toString();
    final action = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: Text((event['bank'] ?? 'Банк').toString()),
      content: SingleChildScrollView(child: SelectableText(
        title.isEmpty ? body : '$title\n$body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 0),
          child: const Text('Закрыть')),
        TextButton(onPressed: () => Navigator.pop(ctx, 2),
          child: const Text('Не операция')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 1),
          child: const Text('Создать операцию')),
      ],
    ));
    if (action == 2) {
      await _archiveNotificationKey((event['key'] ?? '').toString());
    } else if (action == 1 && mounted) {
      await _add(notification: event);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kopilka_entries_v1', jsonEncode(entries));
    await prefs.setDouble('kopilka_goal_v1', goal);
  }

  double _sum(String bank) => entries.fold<double>(0, (sum, e) {
    final amount = safeKopilkaAmount(e);
    if (e['kind'] == 'transfer') {
      if (e['from'] == bank) return sum - amount;
      if (e['to'] == bank) return sum + amount;
      return sum;
    }
    return sum + (e['bank'] == bank ? (e['kind'] == 'income' ? amount : -amount) : 0);
  });

  Future<void> _add({Map<String, dynamic>? notification}) async {
    final notificationText = notification == null ? '' :
        '${notification['title'] ?? ''}\n${notification['body'] ?? ''}';
    String kind = notification == null
        ? 'expense' : suggestNotificationKind(notificationText);
    String bank = banks.first, destination = banks[1];
    String category = 'Другое';
    final notificationBank = notification?['bank']?.toString();
    if (notificationBank != null && banks.contains(notificationBank)) bank = notificationBank;
    final amount = TextEditingController(
      text: notification == null ? '' : suggestNotificationAmount((notification['body'] ?? '').toString()));
    final note = TextEditingController(
      text: notification == null ? '' : (notification['title'] ?? '').toString());
    String? validationError;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        title: const Text('Новая операция'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: kind, decoration: const InputDecoration(labelText: 'Тип'),
            items: const [
              DropdownMenuItem(value: 'expense', child: Text('Расход')),
              DropdownMenuItem(value: 'income', child: Text('Доход')),
              DropdownMenuItem(value: 'transfer', child: Text('Между своими счетами')),
            ], onChanged: (v) { if (v != null) update(() => kind = v); }),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: bank, decoration: InputDecoration(labelText: kind == 'transfer' ? 'Со счёта' : 'Счёт'),
            items: banks.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (v) { if (v != null) update(() => bank = v); }),
          if (kind == 'transfer') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: destination, decoration: const InputDecoration(labelText: 'На счёт'),
              items: banks.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
              onChanged: (v) { if (v != null) update(() => destination = v); }),
          ],
          if (kind == 'expense') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Категория расхода'),
              items: kopilkaExpenseCategories.map((c) =>
                DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (value) { if (value != null) update(() => category = value); },
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Сумма, ₽')),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Комментарий')),
          if (validationError != null) ...[
            const SizedBox(height: 8),
            Text(validationError!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            final value = parseKopilkaAmount(amount.text);
            if (value == null) {
              update(() => validationError = 'Введи положительную сумму, например 1 250,50');
              return;
            }
            if (kind == 'transfer' && bank == destination) {
              update(() => validationError = 'Для перевода выбери разные счета');
              return;
            }
            Navigator.pop(dialogContext, true);
          }, child: const Text('Сохранить')),
        ],
      )));
    if (saved == true) {
      final key = notification?['key']?.toString().trim();
      // Recheck immediately before insertion: another open dialog may have
      // imported the same event while this one awaited user confirmation.
      if (notification != null &&
          (key == null || key.isEmpty ||
              isKopilkaNotificationImported(entries, key))) {
        if (key != null && key.isNotEmpty) await _archiveNotificationKey(key);
        amount.dispose();
        note.dispose();
        return;
      }
      final value = parseKopilkaAmount(amount.text)!;
      setState(() => entries.insert(0, {
        'kind': kind, 'amount': value, 'bank': bank, 'from': bank, 'to': destination,
        'note': note.text.trim(), 'date': DateTime.now().toIso8601String(),
        if (kind == 'expense') 'category': category,
        if (notification != null) 'notificationKey': key,
      }));
      await _save();
      if (notification != null) {
        final key = (notification['key'] ?? '').toString();
        if (key.isNotEmpty) {
          await _archiveNotificationKey(key);
        }
      }
    }
    amount.dispose(); note.dispose();
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: goal.toStringAsFixed(0));
    final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Цель накоплений'),
      content: TextField(controller: controller, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Сумма, ₽')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () {
          final v = parseKopilkaAmount(controller.text);
          if (v != null) Navigator.pop(ctx, v);
        }, child: const Text('Сохранить')),
      ],
    ));
    controller.dispose();
    if (result != null) { setState(() => goal = result); await _save(); }
  }

  @override
  Widget build(BuildContext context) {
    final total = banks.fold<double>(0, (s, b) => s + _sum(b));
    final income = entries.where((e) => e['kind'] == 'income')
      .fold<double>(0, (s, e) => s + safeKopilkaAmount(e));
    final expenses = entries.where((e) => e['kind'] == 'expense')
      .fold<double>(0, (s, e) => s + safeKopilkaAmount(e));
    final now = DateTime.now();
    final monthlyEntries = entries.where((e) {
      final date = DateTime.tryParse((e['date'] ?? '').toString());
      return date != null && date.year == now.year && date.month == now.month;
    }).toList();
    final monthlyIncome = monthlyEntries.where((e) => e['kind'] == 'income')
      .fold<double>(0, (sum, e) => sum + safeKopilkaAmount(e));
    final monthlyExpenses = monthlyEntries.where((e) => e['kind'] == 'expense')
      .fold<double>(0, (sum, e) => sum + safeKopilkaAmount(e));
    final monthlyBalance = monthlyIncome - monthlyExpenses;
    final monthlyCategories = summarizeKopilkaExpenses(monthlyEntries);
    final sortedCategories = monthlyCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // Reuse the same filtered list for display and summary. Transfers between
    // own accounts do not inflate income or expense totals.
    final filteredEntries = entries.where(
      (entry) => matchesKopilkaHistory(entry, historyQuery),
    ).toList();
    final filteredIncome = filteredEntries.where((entry) => entry['kind'] == 'income')
        .fold<double>(0, (sum, entry) => sum + safeKopilkaAmount(entry));
    final filteredExpenses = filteredEntries.where((entry) => entry['kind'] == 'expense')
        .fold<double>(0, (sum, entry) => sum + safeKopilkaAmount(entry));
    // Internal transfers affect neither income nor expenses, but remain
    // visible in the filtered operation summary for reconciliation.
    final filteredTransfers = filteredEntries.where((entry) => entry['kind'] == 'transfer').length;
    final incompleteTransfers = countIncompleteKopilkaTransfers(filteredEntries);
    final incompleteSuffix = incompleteTransfers > 0
        ? ' · Неполных переводов: $incompleteTransfers' : '';
    String money(double value) {
      final parts = value.toStringAsFixed(2).split('.');
      final digits = parts.first.replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ' ');
      return '$digits,${parts.last} ₽';
    }
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.savings_outlined, color: Color(0xFFA8C5FF)), SizedBox(width: 10), Text('КОПИЛКА', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2))]), actions: [
        IconButton(tooltip: 'Цель', icon: const Icon(Icons.flag_outlined), onPressed: _editGoal),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add,
        icon: const Icon(Icons.add), label: const Text('Операция')),
      body: loading ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF193D82), Color(0xFF0E1D38), Color(0xFF151329)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: const Color(0xFF406FB7)),
          ),
          child: Row(children: [
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VEYRION', style: TextStyle(
                  color: Color(0xFF71D7FF), letterSpacing: 3,
                  fontSize: 12, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text('МОЯ КОПИЛКА', style: TextStyle(
                  fontSize: 25, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('Контроль денег. Свои правила.',
                  style: TextStyle(color: Color(0xFFC5D9F5))),
              ],
            )),
            const Icon(Icons.savings_rounded, size: 82, color: Color(0xFF71D7FF)),
          ]),
        ),
        const SizedBox(height: 12),
        Card(color: const Color(0xFF162743), child: Column(children: [
          ListTile(
            leading: Icon(notificationsEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
              color: const Color(0xFFA8C5FF)),
            title: Text(notificationsEnabled ? 'Доступ к уведомлениям включён' : 'Подключить уведомления банков'),
            subtitle: const Text('Т-Банк, Газпромбанк, Ozon Банк. Уведомления остаются на устройстве.'),
            trailing: IconButton(icon: const Icon(Icons.settings_outlined),
              onPressed: _openNotificationSettings),
          ),
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Диагностика получения уведомлений'),
            subtitle: Text(describeKopilkaListener(listenerDiagnostics)),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('События от каждого банка'),
            subtitle: Text(describeKopilkaBankEvents(listenerDiagnostics)),
          ),
          if (pendingNotifications.isNotEmpty)
            ExpansionTile(
              title: Text('На проверке: ${pendingNotifications.length}'),
              subtitle: const Text('Операции не меняют баланс до подтверждения.'),
              children: [
                for (final event in pendingNotifications.reversed.take(visiblePendingCount))
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text((event['bank'] ?? 'Банк').toString()),
                    subtitle: Text((event['title'] ?? 'Уведомление').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _reviewNotification(event),
                  ),
                if (pendingNotifications.length > visiblePendingCount)
                  TextButton(
                    onPressed: () => setState(() => visiblePendingCount += 10),
                    child: Text('Показать ещё уведомления '
                      '(${pendingNotifications.length - visiblePendingCount} осталось)'),
                  ),
              ],
            ),
          TextButton.icon(onPressed: _refreshNotifications,
            icon: const Icon(Icons.refresh), label: const Text('Проверить подключение')),
        ])),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFA8C5FF)), SizedBox(width: 8), Text('Деньги на счетах', style: TextStyle(color: Colors.white70))]),
            const SizedBox(height: 8),
            Text(money(total), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Расчёт по внесённым операциям, не баланс банков', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: (total / goal).clamp(0.0, 1.0)),
            const SizedBox(height: 8),
            Text('Цель: ${money(goal)}'),
          ]))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Card(child: ListTile(title: const Text('Доходы за всё время'), subtitle: Text(money(income))))),
          Expanded(child: Card(child: ListTile(title: const Text('Расходы за всё время'), subtitle: Text(money(expenses))))),
        ]),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Этот месяц', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Поступило', style: TextStyle(color: Colors.white70)),
                Text(money(monthlyIncome), style: const TextStyle(fontWeight: FontWeight.w700)),
              ])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Потрачено', style: TextStyle(color: Colors.white70)),
                Text(money(monthlyExpenses), style: const TextStyle(fontWeight: FontWeight.w700)),
              ])),
            ]),
            const Divider(height: 24),
            Text('Разница: ${money(monthlyBalance)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Операций за месяц: ${monthlyEntries.length}. Переводы между своими счетами не считаются расходами.',
              style: const TextStyle(color: Colors.white70)),
          ],
        ))),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Расходы по категориям за месяц',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Категорию выбираешь при добавлении операции. Старые записи не меняются.',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
            if (sortedCategories.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 12),
                child: Text('Пока нет расходов за этот месяц.')),
            for (final item in sortedCategories) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(item.key)),
                Text(money(item.value)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: monthlyExpenses > 0
                ? (item.value / monthlyExpenses).clamp(0.0, 1.0) : 0),
            ],
          ]),
        )),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Счета', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        for (final bank in banks) Card(child: ListTile(leading: Icon(bank == 'Наличные' ? Icons.payments_outlined : Icons.account_balance_outlined, color: const Color(0xFFA8C5FF)),
          title: Text(bank), trailing: Text(money(_sum(bank))))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('История операций', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        if (entries.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: historySearchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Описание, счёт, дата или сумма',
              helperText: 'Сумма: sum:1250.50  •  min:500  •  max:2000\nТип: тип:расход  •  тип:доход  •  тип:перевод\nБанк: bank:ozon  •  банк:т-банк\nПереводы: from:т-банк  •  to:ozon\nДата: date:2026-10-28  •  дата:28.10.2026\nПериод: с:01.10.2026  •  по:29.10.2026\nЗаметка: note:кофе  •  заметка:продукты\nЕсть описание: has:note  •  без описания: has:no-note\nПроверка дат: has:date  •  has:no-date\nСчёт: has:bank  •  has:no-bank\nСумма записи: has:amount  •  has:no-amount\nПеревод без счёта: has:no-from  •  has:no-to\nИсключить слово: -такси',
              helperMaxLines: 13,
              border: const OutlineInputBorder(),
              suffixIcon: historyQuery.isEmpty ? null : IconButton(
                tooltip: 'Очистить поиск',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  historySearchController.clear();
                  setState(() => historyQuery = '');
                },
              ),
            ),
            onChanged: (value) => setState(() => historyQuery = value),
          ),
        ),
        if (entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${historyQuery.trim().isEmpty ? 'Всего' : 'Найдено'}: ${filteredEntries.length} из ${entries.length} · Доходы: ${money(filteredIncome)} · Расходы: ${money(filteredExpenses)}\nРазница: ${money(kopilkaNetChange(filteredEntries))} · Переводов: $filteredTransfers$incompleteSuffix',
              style: const TextStyle(color: Colors.white70)),
          ),
        if (entries.isNotEmpty && filteredEntries.isEmpty)
          ListTile(
            title: const Text('Операции не найдены'),
            subtitle: const Text('Попробуй изменить или очистить фильтр.'),
            trailing: TextButton(
              onPressed: () {
                historySearchController.clear();
                setState(() => historyQuery = '');
              },
              child: const Text('Сбросить'),
            ),
          ),
        if (entries.isEmpty) const ListTile(title: Text('Пока нет операций'),
          subtitle: Text('Нажми «Операция», чтобы внести начальные остатки, расходы или перевод между своими счетами.')),
        for (final e in filteredEntries) Card(child: ListTile(
          leading: Icon(e['kind'] == 'transfer' ? Icons.swap_horiz :
            e['kind'] == 'income' ? Icons.arrow_downward : Icons.arrow_upward),
          title: Text(e['kind'] == 'transfer' ? '${e['from']} → ${e['to']}' :
            (e['note'] ?? '').toString().isEmpty ? (e['kind'] == 'income' ? 'Доход' : 'Расход') : e['note'].toString()),
          subtitle: Text(e['kind'] == 'transfer' ? 'Перевод между своими счетами' :
            e['kind'] == 'expense'
                ? '${(e['bank'] ?? 'Неизвестный счёт')} · ${kopilkaExpenseCategory(e)}'
                : (e['bank'] ?? 'Неизвестный счёт').toString()),
          trailing: Text(money(safeKopilkaAmount(e))),
          onLongPress: () async {
            final remove = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Удалить операцию?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
              ],
            ));
            if (remove == true && mounted) {
              final originalIndex = entries.indexOf(e);
              if (originalIndex < 0) return;
              setState(() => entries.removeAt(originalIndex));
              await _save();
              if (!mounted) return;
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Операция удалена'),
                duration: const Duration(seconds: 7),
                action: SnackBarAction(label: 'Отменить', onPressed: () async {
                  if (!mounted || entries.contains(e)) return;
                  setState(() => entries.insert(
                    originalIndex.clamp(0, entries.length), e));
                  await _save();
                }),
              ));
            }
          },
        )),
        const SizedBox(height: 90),
      ]),
    );
  }
}
