import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Suggests an amount for manual review. Balance-only notifications must
/// not be prefilled as expenses; the user still confirms every operation.
String suggestNotificationAmount(String body) {
  final amountPattern = RegExp(
    r'(\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,](\d{1,2}))?\s*(?:₽|руб(?:\.|ля|лей)?|RUB)',
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
      bestScore = score;
      final whole = match.group(1)!.replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
      final decimals = match.group(2);
      result = decimals == null ? whole : '$whole.$decimals';
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
    r'₽|руб(?:\.|ля|лей)?|\bRUB\b',
    caseSensitive: false,
  );
  final sensitive = RegExp(
    r'код\s+(?:подтверждения|входа|для\s+(?:входа|подтверждения)|операции|из\s+смс)|(?:sms|смс)[-\s]*код|одноразов(?:ый|ого)\s+код|никому\s+не\s+сообщайте|verification\s+code|one[- ]time\s+(?:password|code)|\bOTP\b',
    caseSensitive: false,
  );
  return transaction.hasMatch(text) &&
      currency.hasMatch(text) &&
      !sensitive.hasMatch(text);
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
        if (key.isEmpty || normalizedReviewed.contains(key)) return false;
        if (!isBankTransactionNotification(
            (e['title'] ?? '').toString(), (e['body'] ?? '').toString())) {
          return false;
        }
        if (!seen.add(key)) return false;
        // Store the canonical ID so later refreshes cannot re-import it.
        e['key'] = key;
        return true;
      }).toList();
}


/// Invalid legacy amounts must never crash totals or contaminate balances.
double safeKopilkaAmount(Map<String, dynamic> entry) {
  final value = entry['amount'];
  return value is num && value.isFinite ? value.toDouble() : 0.0;
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

/// Local search of already saved transactions; never sends finance data online.
bool matchesKopilkaHistory(Map<String, dynamic> entry, String query) {
  // Normalize Russian thousands separators and decimal commas for searching.
  // The saved transaction itself is never modified.
  final normalizedQuery = query.toLowerCase().trim()
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
  final words = normalizedQuery.split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final text = [
    entry['note'], entry['bank'], entry['from'], entry['to'],
    entry['date'], entry['kind'], entry['amount'],
    entry['kind'] == 'income' ? 'доход поступление' :
      entry['kind'] == 'expense' ? 'расход покупка' : 'перевод',
  ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
  return words.every(text.contains);
}

/// Local-first finance notebook. No bank credentials or transactions leave the device.
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

  Future<void> _reviewNotification(Map<String, dynamic> event) async {
    final title = (event['title'] ?? '').toString();
    final body = (event['body'] ?? '').toString();
    final add = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text((event['bank'] ?? 'Банк').toString()),
      content: SingleChildScrollView(child: SelectableText(
        title.isEmpty ? body : '$title\n$body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Закрыть')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Создать операцию')),
      ],
    ));
    if (add == true && mounted) await _add(notification: event);
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
      final value = parseKopilkaAmount(amount.text)!;
      setState(() => entries.insert(0, {
        'kind': kind, 'amount': value, 'bank': bank, 'from': bank, 'to': destination,
        'note': note.text.trim(), 'date': DateTime.now().toIso8601String(),
        if (notification != null) 'notificationKey': (notification['key'] ?? '').toString(),
      }));
      await _save();
      if (notification != null) {
        final key = (notification['key'] ?? '').toString();
        if (key.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final reviewed = prefs.getStringList('kopilka_reviewed_notifications_v1') ?? <String>[];
          reviewed.remove(key);
          reviewed.add(key);
          if (reviewed.length > 500) reviewed.removeRange(0, reviewed.length - 500);
          await prefs.setStringList('kopilka_reviewed_notifications_v1', reviewed);
          if (mounted) {
            setState(() => pendingNotifications.removeWhere((e) => e['key'] == key));
          }
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
              hintText: 'Поиск по описанию, счёту, дате или сумме',
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
        if (entries.isNotEmpty && !entries.any((e) => matchesKopilkaHistory(e, historyQuery)))
          const ListTile(title: Text('Операции не найдены')),
        if (entries.isEmpty) const ListTile(title: Text('Пока нет операций'),
          subtitle: Text('Нажми «Операция», чтобы внести начальные остатки, расходы или перевод между своими счетами.')),
        for (final e in entries.where((e) => matchesKopilkaHistory(e, historyQuery))) Card(child: ListTile(
          leading: Icon(e['kind'] == 'transfer' ? Icons.swap_horiz :
            e['kind'] == 'income' ? Icons.arrow_downward : Icons.arrow_upward),
          title: Text(e['kind'] == 'transfer' ? '${e['from']} → ${e['to']}' :
            (e['note'] ?? '').toString().isEmpty ? (e['kind'] == 'income' ? 'Доход' : 'Расход') : e['note'].toString()),
          subtitle: Text(e['kind'] == 'transfer' ? 'Перевод между своими счетами' : (e['bank'] ?? 'Неизвестный счёт').toString()),
          trailing: Text(money(safeKopilkaAmount(e))),
          onLongPress: () async {
            final remove = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Удалить операцию?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
              ],
            ));
            if (remove == true) { setState(() => entries.remove(e)); await _save(); }
          },
        )),
        const SizedBox(height: 90),
      ]),
    );
  }
}
