import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-first finance notebook. No bank credentials or transactions leave the device.
class KopilkaPage extends StatefulWidget {
  const KopilkaPage({super.key});
  @override
  State<KopilkaPage> createState() => _KopilkaPageState();
}

class _KopilkaPageState extends State<KopilkaPage> with WidgetsBindingObserver {
  final entries = <Map<String, dynamic>>[];
  bool loading = true;
  static const _notifications = MethodChannel('kopilka/notifications');
  bool notificationsEnabled = false;
  final pendingNotifications = <Map<String, dynamic>>[];
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
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString('kopilka_entries_v1') ?? '[]') as List;
      entries.addAll(saved.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {}
    if (!mounted) return;
    setState(() { goal = prefs.getDouble('kopilka_goal_v1') ?? 100000; loading = false; });
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
      final data = (jsonDecode(raw) as List).whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => !reviewed.contains((e['key'] ?? '').toString()))
          .toList();
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

  String _suggestAmount(String body) {
    // This is only a hint: the user confirms the amount and type manually.
    final match = RegExp(r'(\d[\d \u00a0]*[.,]?\d{0,2})\s*(?:₽|руб\.?|RUB)',
        caseSensitive: false).firstMatch(body);
    return match?.group(1)?.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.') ?? '';
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
    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
    if (e['kind'] == 'transfer') {
      if (e['from'] == bank) return sum - amount;
      if (e['to'] == bank) return sum + amount;
      return sum;
    }
    return sum + (e['bank'] == bank ? (e['kind'] == 'income' ? amount : -amount) : 0);
  });

  Future<void> _add({Map<String, dynamic>? notification}) async {
    String kind = 'expense', bank = banks.first, destination = banks[1];
    final notificationBank = notification?['bank']?.toString();
    if (notificationBank != null && banks.contains(notificationBank)) bank = notificationBank;
    final amount = TextEditingController(
      text: notification == null ? '' : _suggestAmount((notification['body'] ?? '').toString()));
    final note = TextEditingController(
      text: notification == null ? '' : (notification['title'] ?? '').toString());
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
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            final value = double.tryParse(amount.text.trim().replaceAll(',', '.'));
            if (value == null || !value.isFinite || value <= 0 || (kind == 'transfer' && bank == destination)) return;
            Navigator.pop(dialogContext, true);
          }, child: const Text('Сохранить')),
        ],
      )));
    if (saved == true) {
      final value = double.parse(amount.text.trim().replaceAll(',', '.'));
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
          final v = double.tryParse(controller.text.replaceAll(',', '.'));
          if (v != null && v.isFinite && v > 0) Navigator.pop(ctx, v);
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
      .fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());
    final expenses = entries.where((e) => e['kind'] == 'expense')
      .fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());
    final now = DateTime.now();
    final monthlyEntries = entries.where((e) {
      final date = DateTime.tryParse((e['date'] ?? '').toString());
      return date != null && date.year == now.year && date.month == now.month;
    }).toList();
    final monthlyIncome = monthlyEntries.where((e) => e['kind'] == 'income')
      .fold<double>(0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0));
    final monthlyExpenses = monthlyEntries.where((e) => e['kind'] == 'expense')
      .fold<double>(0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0));
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
                for (final event in pendingNotifications.reversed.take(10))
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text((event['bank'] ?? 'Банк').toString()),
                    subtitle: Text((event['title'] ?? 'Уведомление').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _reviewNotification(event),
                  ),
                if (pendingNotifications.length > 10)
                  const Padding(padding: EdgeInsets.all(8),
                    child: Text('Показаны 10 последних уведомлений.')),
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
        if (entries.isEmpty) const ListTile(title: Text('Пока нет операций'),
          subtitle: Text('Нажми «Операция», чтобы внести начальные остатки, расходы или перевод между своими счетами.')),
        for (final e in entries) Card(child: ListTile(
          leading: Icon(e['kind'] == 'transfer' ? Icons.swap_horiz :
            e['kind'] == 'income' ? Icons.arrow_downward : Icons.arrow_upward),
          title: Text(e['kind'] == 'transfer' ? '${e['from']} → ${e['to']}' :
            (e['note'] as String).isEmpty ? (e['kind'] == 'income' ? 'Доход' : 'Расход') : e['note'] as String),
          subtitle: Text(e['kind'] == 'transfer' ? 'Перевод между своими счетами' : e['bank'] as String),
          trailing: Text(money((e['amount'] as num).toDouble())),
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
