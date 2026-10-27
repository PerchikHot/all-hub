import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-first finance notebook. No bank credentials or transactions leave the device.
class KopilkaPage extends StatefulWidget {
  const KopilkaPage({super.key});
  @override
  State<KopilkaPage> createState() => _KopilkaPageState();
}

class _KopilkaPageState extends State<KopilkaPage> {
  final entries = <Map<String, dynamic>>[];
  bool loading = true;
  double goal = 100000;
  final banks = const ['Т-Банк', 'Газпромбанк', 'Ozon Банк', 'Наличные'];
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString('kopilka_entries_v1') ?? '[]') as List;
      entries.addAll(saved.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {}
    if (!mounted) return;
    setState(() { goal = prefs.getDouble('kopilka_goal_v1') ?? 100000; loading = false; });
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

  Future<void> _add() async {
    String kind = 'expense', bank = banks.first, destination = banks[1];
    final amount = TextEditingController(), note = TextEditingController();
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
      }));
      await _save();
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
    String money(double value) {
      final parts = value.toStringAsFixed(2).split('.');
      final digits = parts.first.replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ' ');
      return '$digits,${parts.last} ₽';
    }
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.savings_outlined, color: Color(0xFFA8C5FF)), SizedBox(width: 10), Text('Копилка')]), actions: [
        IconButton(tooltip: 'Цель', icon: const Icon(Icons.flag_outlined), onPressed: _editGoal),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add,
        icon: const Icon(Icons.add), label: const Text('Операция')),
      body: loading ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(16), children: [
        Card(color: const Color(0xFF162743), child: const ListTile(
          leading: Icon(Icons.notifications_off_outlined, color: Color(0xFFA8C5FF)),
          title: Text('Автоучёт пока не подключён'),
          subtitle: Text('Уведомления Т-Банка, Газпромбанка и Ozon Банка ещё не считываются. Операции сейчас добавляются вручную.'),
        )),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Общий баланс', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(money(total), style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: (total / goal).clamp(0.0, 1.0)),
            const SizedBox(height: 8),
            Text('Цель: ${money(goal)}'),
          ]))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Card(child: ListTile(title: const Text('Доходы'), subtitle: Text(money(income))))),
          Expanded(child: Card(child: ListTile(title: const Text('Расходы'), subtitle: Text(money(expenses))))),
        ]),
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
