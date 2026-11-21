import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'eyra_file_inspector.dart';
import 'eyra_duplicate_scan.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// These are user preferences, NOT Android/Windows operating-system grants.
/// Every future capability must check both this policy and its OS permission.
class EyraAccessPolicy {
  static const prefix = 'eyra_access_v1_';
  static const capabilities = <String, String>{
    'proactive': 'Инициировать общение',
    'notifications': 'Уведомления',
    'diagnostics': 'Диагностика устройства',
    'files': 'Действия с файлами',
    'apps': 'Управление приложениями',
    'sync': 'Синхронизация устройств',
  };
  static Future<bool> enabled(String id) async {
    if (!capabilities.containsKey(id)) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$prefix$id') ?? false;
  }
  static Future<bool> set(String id, bool value) async {
    if (!capabilities.containsKey(id)) return false;
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setBool('$prefix$id', value);
    if (ok) await appendLog('${capabilities[id]}: ${value ? "запрошено" : "отозвано"}');
    return ok;
  }
  static Future<void> appendLog(String message) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList('${prefix}audit') ?? <String>[];
    final item = jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), 'event': message});
    await prefs.setStringList('${prefix}audit', [...entries, item].takeLast(100).toList());
  }
}

extension _LastItems<T> on Iterable<T> {
  Iterable<T> takeLast(int n) {
    final items = toList();
    return items.skip(items.length > n ? items.length - n : 0);
  }
}

/// A transparent preparation screen. No background service or remote transfer
/// is started by changing any preference on this screen.
class EyraAccessPage extends StatefulWidget {
  const EyraAccessPage({super.key});
  @override
  State<EyraAccessPage> createState() => _EyraAccessPageState();
}

class _EyraAccessPageState extends State<EyraAccessPage> {
  Map<String, bool> choices = {};
  List<String> audit = [];
  bool loading = true;
  bool saving = false;
  bool diagnosing = false;
  String? diagnosticResult;
  bool inspectingFile = false;
  String? fileResult;
  bool scanningDuplicates = false;
  String? duplicateResult;
  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, bool>{
      for (final id in EyraAccessPolicy.capabilities.keys)
        id: prefs.getBool('${EyraAccessPolicy.prefix}$id') ?? false,
    };
    if (mounted) setState(() {
      choices = values;
      audit = prefs.getStringList('${EyraAccessPolicy.prefix}audit') ?? [];
      loading = false;
    });
  }

  Future<void> change(String id, bool enabled) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final ok = await EyraAccessPolicy.set(id, enabled);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить настройку')));
      }
      if (mounted && !enabled) setState(() {
        if (id == 'diagnostics') diagnosticResult = null;
        if (id == 'files') { fileResult = null; duplicateResult = null; }
      });
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> revokeAll() async {
    if (saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отозвать все разрешения Эйры?'),
        content: const Text('Все настройки доступа будут выключены. История действий сохранится. Это не меняет системные разрешения Android или Windows.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отозвать')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      for (final id in EyraAccessPolicy.capabilities.keys) {
        if (await EyraAccessPolicy.enabled(id)) await EyraAccessPolicy.set(id, false);
      }
      if (mounted) setState(() { diagnosticResult = null; fileResult = null; duplicateResult = null; });
      await refresh();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Explicit foreground-only diagnostic. No file access, network requests,
  /// process enumeration, identifiers or background monitoring.
  Future<void> runDiagnostics() async {
    if (saving || diagnosing) return;
    if (!await EyraAccessPolicy.enabled('diagnostics')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала включите диагностику')));
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Проверить устройство сейчас?'),
        content: const Text('Эйра определит только платформу и версию ОС. Данные будут показаны на экране, не отправятся в сеть и не сохранятся в журнале. Никаких файлов или приложений проверка не читает.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Проверить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => diagnosing = true);
    try {
      // Recheck consent after confirmation to respect revocation.
      if (!await EyraAccessPolicy.enabled('diagnostics')) return;
      final result = 'Платформа: ${Platform.operatingSystem}\nВерсия ОС: ${Platform.operatingSystemVersion}\n'
          'Сеть: не проверялась\nФайлы и приложения: не проверялись';
      await EyraAccessPolicy.appendLog('Диагностика запущена вручную (без сохранения результатов)');
      if (mounted) setState(() => diagnosticResult = result);
      await refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось выполнить диагностику')));
    } finally {
      if (mounted) setState(() => diagnosing = false);
    }
  }

  /// Foreground-only inspection of a file the user explicitly selects.
  /// Never stores file bytes or uploads content; only an opt-in SHA-256 digest.
  Future<void> inspectSelectedFile() async {
    if (saving || inspectingFile || !await EyraAccessPolicy.enabled('files')) return;
    if (!mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any, allowMultiple: false, withData: false);
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final path = picked.files.single.path;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не удалось получить доступ к выбранному файлу')));
      return;
    }
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Проверить выбранный файл?'),
        content: const Text('Будут прочитаны размер и SHA-256 только этого файла. Файл не изменяется, содержимое не сохраняется и не отправляется в сеть. Максимальный размер — 256 МиБ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Проверить')),
        ],
      ));
    if (confirmed != true || !mounted ||
        !await EyraAccessPolicy.enabled('files')) return;
    setState(() { inspectingFile = true; fileResult = null; });
    try {
      final info = await EyraFileInspector.inspect(File(path));
      if (!await EyraAccessPolicy.enabled('files')) return;
      await EyraAccessPolicy.appendLog('Проверка выбранного файла (без сохранения имени и содержимого)');
      if (mounted) setState(() => fileResult =
          'Файл: ${picked.files.single.name}\\nРазмер: ${info.bytes} байт\\nSHA-256: ${info.sha256}');
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось проверить файл: $e')));
    } finally {
      if (mounted) setState(() => inspectingFile = false);
    }
  }


  /// Only user-selected files are read; nothing is deleted or uploaded.
  Future<void> findSelectedDuplicates() async {
    if (saving || scanningDuplicates ||
        !await EyraAccessPolicy.enabled('files')) return;
    if (!mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any, allowMultiple: true, withData: false);
    if (picked == null || !mounted) return;
    if (picked.files.length < 2 || picked.files.length > EyraDuplicateScan.maxFiles ||
        picked.files.any((file) => file.path == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Выбери от 2 до 30 доступных файлов')));
      return;
    }
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Найти одинаковые файлы?'),
        content: Text('Будут прочитаны только выбранные ${picked.files.length} файлов '
          '(до 256 МиБ каждый) и вычислены SHA-256. Ничего не удаляется, '
          'не отправляется в сеть и не сохраняется.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Проверить')),
        ],
      ));
    if (confirmed != true || !mounted ||
        !await EyraAccessPolicy.enabled('files')) return;
    setState(() { scanningDuplicates = true; duplicateResult = null; });
    try {
      final matches = await EyraDuplicateScan.scan(
        picked.files.map((file) => File(file.path!)).toList(),
        stillAllowed: () => EyraAccessPolicy.enabled('files'));
      if (!await EyraAccessPolicy.enabled('files')) return;
      final result = matches.isEmpty
        ? 'Совпадающих файлов среди выбранных нет.'
        : matches.map((group) =>
            '${group.names.length} совпадения (${group.bytes} байт): '
            '${group.names.join(", ")}').join('\n');
      await EyraAccessPolicy.appendLog(
        'Ручной поиск дубликатов среди ${picked.files.length} файлов; '
        'групп: ${matches.length} (без сохранения путей)');
      if (mounted) setState(() => duplicateResult = result);
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Поиск дубликатов не выполнен: $e')));
    } finally {
      if (mounted) setState(() => scanningDuplicates = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const explanations = <String, String>{
      'proactive': 'Только настройка предпочтения. Самостоятельная отправка сообщений пока не реализована.',
      'notifications': 'Системные уведомления пока не подключены. Никаких фоновых уведомлений эта настройка не запускает.',
      'diagnostics': 'Разрешает только ручную проверку платформы и версии ОС после отдельного подтверждения. Без фонового сбора.',
      'files': 'Ручная проверка файла и поиск дубликатов среди выбранных файлов после подтверждения. Без удаления, изменения и фонового доступа.',
      'apps': 'Не даёт права устанавливать, запускать или удалять приложения.',
      'sync': 'Синхронизация пока не реализована: переписки и память остаются на текущем устройстве.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Эйра · доступ и приватность')),
      body: loading ? const Center(child: CircularProgressIndicator()) :
        ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Контроль доступа', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Все переключатели выключены по умолчанию. Это предварительные согласия внутри All Hub, а НЕ системные разрешения. Пока соответствующие функции не реализованы, включение ничего не запускает.'),
              const SizedBox(height: 8),
              const Text('Фоновая активность: отключена. Обмен между устройствами: отсутствует. Данные хранятся локально.'),
            ],
          ))),
          const SizedBox(height: 8),
          for (final entry in EyraAccessPolicy.capabilities.entries)
            Card(child: SwitchListTile.adaptive(
              title: Text(entry.value),
              subtitle: Text(explanations[entry.key]!),
              value: choices[entry.key] ?? false,
              onChanged: saving ? null : (value) => change(entry.key, value),
            )),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Диагностика по запросу', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('Без скрытого мониторинга: только ОС и её версия. Результат не отправляется и не сохраняется.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('eyra-run-diagnostics'),
                onPressed: saving || diagnosing || !(choices['diagnostics'] ?? false)
                    ? null : runDiagnostics,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(diagnosing ? 'Проверяем…' : 'Проверить сейчас'),
              ),
              if (diagnosticResult != null) ...[
                const SizedBox(height: 8),
                SelectableText(diagnosticResult!),
                TextButton(
                  onPressed: () => setState(() => diagnosticResult = null),
                  child: const Text('Скрыть результат'),
                ),
              ],
            ],
          ))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Проверка файла', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('Выбери файл самостоятельно: Эйра покажет размер и SHA-256. Ничего не изменяет и не отправляет в сеть.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: saving || inspectingFile || !(choices['files'] ?? false)
                    ? null : inspectSelectedFile,
                icon: const Icon(Icons.file_present_outlined),
                label: Text(inspectingFile ? 'Проверяем…' : 'Выбрать и проверить файл'),
              ),
              const SizedBox(height: 12),
              const Text('Поиск дубликатов: выбери 2–30 файлов. '
                'Сравнивается содержимое, не только имена. Удаления нет.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('eyra-find-duplicates'),
                onPressed: saving || scanningDuplicates ||
                    !(choices['files'] ?? false) ? null : findSelectedDuplicates,
                icon: const Icon(Icons.content_copy_outlined),
                label: Text(scanningDuplicates ? 'Сравниваем…' : 'Найти дубликаты'),
              ),
              if (duplicateResult != null) ...[
                const SizedBox(height: 8),
                SelectableText(duplicateResult!),
                TextButton(onPressed: () => setState(() => duplicateResult = null),
                  child: const Text('Скрыть результат')),
              ],
              if (fileResult != null) ...[
                const SizedBox(height: 8),
                SelectableText(fileResult!),
                TextButton(onPressed: () => setState(() => fileResult = null),
                  child: const Text('Скрыть результат')),
              ],
            ],
          ))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: saving ? null : revokeAll,
            icon: const Icon(Icons.lock_reset),
            label: const Text('Отозвать всё'),
          ),
          const SizedBox(height: 20),
          Text('Локальный журнал настроек', style: Theme.of(context).textTheme.titleMedium),
          const Text('Показывает изменения согласий, а не реальные действия с устройством. Новые записи хранятся только здесь (до 100).'),
          if (audit.isEmpty) const Padding(
            padding: EdgeInsets.all(12), child: Text('Записей пока нет')),
          for (final raw in audit.reversed.take(30))
            ListTile(dense: true, leading: const Icon(Icons.history),
              title: Text(_event(raw)), subtitle: Text(_date(raw))),
        ]),
    );
  }

  String _event(String raw) {
    try { return (jsonDecode(raw) as Map<String, dynamic>)['event']?.toString() ?? 'Событие'; }
    catch (_) { return 'Повреждённая запись'; }
  }
  String _date(String raw) {
    try { return (jsonDecode(raw) as Map<String, dynamic>)['time']?.toString() ?? ''; }
    catch (_) { return ''; }
  }
}
