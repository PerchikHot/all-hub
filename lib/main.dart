import 'project_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hub_liquid_progress.dart';
import 'hub_wait_indicator.dart';
import 'project_launcher.dart';
import 'project_download_progress.dart';
import 'external_repositories.dart';
import 'external_artwork.dart';
import 'external_screenshots.dart';
import 'version_status.dart';
import 'media_browser_page.dart';
import 'kopilka_page.dart';
import 'dart:io';
import 'hub_service.dart';
import 'hub_widgets.dart';
import 'development_center.dart';
import 'project_covers.dart';
import 'ai_models_page.dart';
import 'media_search_page.dart';
import 'snapshot_pack_creator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AllHub());
  // A successful process spawn is not a successful app startup. Only confirm
  // the Windows handoff after Flutter has rendered its first application frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await ProjectLauncher.reconcileAllHubWindowsHandoff();
    } catch (error) {
      // Leave the receipt unconfirmed: the external updater will roll back.
      debugPrint('Windows update receipt reconciliation failed: $error');
    }
  });
}

class Project {
  final String id, name, type, description;
  final String? repo;
  const Project(this.id, this.name, this.type, this.description, this.repo);
  factory Project.fromJson(Map<String, dynamic> x) => Project(
    x['id'] as String, x['name'] as String, x['type'] as String,
    x['description'] as String, x['repo'] as String?);
}

class GithubInfo {
  final String? version, downloadUrl, workflowStatus, actionsUrl;
  final String? error, releaseNotes, sha256Digest;
  const GithubInfo({this.version, this.downloadUrl, this.workflowStatus, this.actionsUrl, this.error, this.releaseNotes, this.sha256Digest});
}

class GithubApi {
  static Future<GithubInfo> inspect(String repo, {String? projectId}) async {
    final result = await HubService.inspect(repo,
        projectId: projectId?.startsWith('external-') == true ? null : projectId);
    final available = HubService.preferredInstallAssets(
      result.assets.where((a) {
        final name = a.name.toLowerCase();
        if (projectId == 'kopilka') return name.startsWith('kopilka-');
        if (projectId == 'all-hub') {
          return name.startsWith('allhub-') || name.startsWith('all-hub-');
        }
        return true;
      }), currentPlatform);
    return GithubInfo(
      version: available.isEmpty ? null : available.first.version,
      downloadUrl: available.isEmpty ? null : available.first.url,
      workflowStatus: result.workflow,
      actionsUrl: result.actionsUrl,
      error: result.error,
      releaseNotes: available.isEmpty ? null : available.first.releaseNotes,
      sha256Digest: available.isEmpty ? null : available.first.sha256Digest,
    );
  }
}

class AllHub extends StatefulWidget {
  const AllHub({super.key});
  @override
  State<AllHub> createState() => _AllHubState();
}

class _AllHubState extends State<AllHub> {
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final value = prefs.getString('all_hub_theme_mode');
      setState(() => mode = value == 'light' ? ThemeMode.light
          : value == 'dark' ? ThemeMode.dark : ThemeMode.system);
    });
  }
  Future<void> setMode(ThemeMode value) async {
    setState(() => mode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('all_hub_theme_mode', value.name);
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'All Hub', debugShowCheckedModeBanner: false,
    themeMode: mode,
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.dark
          ? const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                Color(0xFF08162F),
                Color(0xFF101B40),
                Color(0xFF15102C),
                Color(0xFF070E20),
              ],
              stops: [0, .36, .68, 1],
            )
          : const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFF0F4FC), Color(0xFFE5EDFC)],
            ),
      ),
      child: _ThemeControls(
        mode: mode, onChanged: setMode, child: child!),
    ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4978D4),
        brightness: Brightness.light),
      scaffoldBackgroundColor: const Color(0xFFF0F4FC),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14))),
    ),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF739EFF), brightness: Brightness.dark),
      scaffoldBackgroundColor: Colors.transparent),
    home: const HomePage());
}

class _ThemeControls extends InheritedWidget {
  const _ThemeControls({required this.mode, required this.onChanged,
    required super.child});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  static _ThemeControls of(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_ThemeControls>()!;
  @override
  bool updateShouldNotify(_ThemeControls old) => mode != old.mode;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int tab = 0;
  String category = 'All';
  String? selectedProjectId;
  String search = '';
  final TextEditingController searchController = TextEditingController();
  bool showOnlyAvailable = false;
  bool showCatalogTools = false;
  bool allHubUpdateInProgress = false;
  late Future<List<Project>> projects = _loadProjects();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CoverSettings.load();
    migrateAllHubMedia();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's package installer is external to All Hub. Re-read the
    // installed package version only after the user returns: starting the
    // installer does not prove that installation was approved or completed.
    if (state == AppLifecycleState.resumed && mounted) {
      // Revalidate both installed versions and published releases after
      // returning from the package installer or bringing All Hub to foreground.
      // A stale cached release must not hide a newly available update.
      info.clear();
      installedVersionChecks.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchController.dispose();
    super.dispose();
  }
  final Map<String, Future<GithubInfo>> info = {};
  final Map<String, Future<String?>> installedVersionChecks = {};
  Future<String?> cachedInstalledVersion(String id) =>
    installedVersionChecks.putIfAbsent(
      id, () => ProjectLauncher.installedVersion(id));
  Future<List<Project>> _loadProjects() async {
    final data = await rootBundle.loadString('assets/projects.json');
    final live = await HubService.catalog(data);
    final result = live.map((p) => Project(p.id, p.name, p.type, p.description, p.repo)).toList();
    for (final external in await ExternalRepositoryStore.load()) {
      if (result.any((p) =>
          p.repo?.toLowerCase() == external.fullName.toLowerCase())) {
        continue;
      }
      result.add(Project(external.projectId, external.name,
          'GitHub app', 'Публичный репозиторий: ${external.fullName}',
          external.fullName));
    }
    return result;
  }
  Future<void> addRepository() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('Добавить публичный GitHub-репозиторий'),
        content: TextField(controller: controller, autofocus: true,
          decoration: const InputDecoration(
            hintText: 'owner/repository или https://github.com/owner/repository')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Проверить и добавить')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || entered == null || entered.isEmpty) {
      return;
    }
    final external = ExternalRepository.parse(entered);
    if (external == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Укажи точный owner/repo или адрес публичного репозитория')));
      return;
    }
    try {
      await ExternalRepositoryStore.verifyPublic(external);
      final added = await ExternalRepositoryStore.add(external);
      if (!mounted) {
        return;
      }
      await refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added ? 'Репозиторий добавлен: ${external.fullName}'
            : 'Репозиторий уже есть в каталоге')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить репозиторий: $e')));
    }
  }

  Future<void> copyRepositoryBackup() async {
    try {
      final catalog = await ExternalRepositoryStore.load();
      await Clipboard.setData(ClipboardData(
        text: ExternalRepositoryStore.exportBackup(catalog)));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Скопирован каталог: ${catalog.length} репозиториев. '
            'Только публичные адреса, без данных приложений.')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось скопировать каталог: $e')));
    }
  }

  Future<void> importRepositoryBackup({bool merge = false}) async {
    final clipboard = await Clipboard.getData('text/plain');
    if (!mounted) {
      return;
    }
    final controller = TextEditingController(text: clipboard?.text ?? '');
    final source = await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(merge ? 'Объединить публичные каталоги' : 'Импорт публичных репозиториев'),
        content: SizedBox(width: 540, child: TextField(
          controller: controller, maxLines: 8, minLines: 4,
          decoration: InputDecoration(
            hintText: 'Вставь JSON-каталог All Hub',
            helperText: merge ? 'Добавит новые репозитории, сохранив текущие.' : 'Импорт заменит только список сторонних репозиториев.'),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Проверить')),
        ],
      ));
    controller.dispose();
    if (!mounted || source == null) {
      return;
    }
    try {
      final parsed = ExternalRepositoryStore.parseBackup(source);
      final approved = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text(merge ? 'Добавить новые репозитории?' : 'Заменить каталог?'),
          content: Text(merge
            ? 'Будут добавлены только новые из ${parsed.length} записей. '
              'Все новые адреса проверяются до сохранения. '
              'Существующие репозитории, обложки и установленные приложения не удаляются.'
            : 'Будут проверены ${parsed.length} публичных '
              'GitHub-репозиториев. Текущий список будет заменён только '
              'после успешной проверки всех адресов. '
              'Установленные приложения и их данные останутся без изменений.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(merge ? 'Проверить и добавить' : 'Проверить и импортировать')),
          ],
        ));
      if (approved != true || !mounted) {
        return;
      }
      final count = merge
          ? await ExternalRepositoryStore.mergeBackup(source)
          : await ExternalRepositoryStore.importBackup(source);
      if (!mounted) {
        return;
      }
      await refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(merge ? 'Добавлено новых репозиториев: $count' : 'Импортировано репозиториев: $count')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Каталог не изменён: $e')));
    }
  }

  Future<void> removeRepository(Project project) async {
    final external = ExternalRepository.parse(project.repo ?? '');
    if (external == null || external.projectId != project.id) {
      return;
    }
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('Удалить из каталога?'),
        content: Text('Репозиторий ${external.fullName} исчезнет из списка. '
          'Установленные приложения и их данные не удаляются.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Убрать из каталога')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ExternalRepositoryStore.remove(external);
    await ExternalArtwork.remove(external.projectId);
    await ExternalScreenshots.removeAll(external.projectId);
    if (mounted) {
      await refresh();
    }
  }

  Future<void> chooseExternalArtwork(Project project) async {
    if (!project.id.startsWith('external-')) { return; }
    try {
      final selected = await ExternalArtwork.choose(project.id);
      if (selected && mounted) { setState(() {}); }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось выбрать обложку: $e')));
      }
    }
  }

  Future<void> configureExternalPackage(Project project) async {
    if (!project.id.startsWith('external-')) {
      return;
    }
    final existing = await ProjectLauncher.externalPackageName(project.id);
    if (!mounted) {
      return;
    }
    final controller = TextEditingController(text: existing ?? '');
    final packageName = await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Запуск установленного Android-приложения'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'com.example.app',
            helperText: 'Укажи package ID приложения. Доступ только к запуску, не к его данным.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || packageName == null) {
      return;
    }
    try {
      await ProjectLauncher.setExternalPackageName(project.id, packageName);
      if (mounted) {
        await refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить package ID: $e')));
      }
    }
  }

  Future<bool> confirmExternalInstall(Project project) async {
    if (!project.id.startsWith('external-')) {
      return true;
    }
    return await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('Установить стороннее приложение?'),
        content: Text('Источник: ${project.repo}\n\n'
          'All Hub проверяет адрес релиза, но не может гарантировать '
          'безопасность APK/EXE. Устанавливай только из доверенного '
          'репозитория. Android отдельно запросит подтверждение установки.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Понимаю, продолжить')),
        ],
      ),
    ) ?? false;
  }

  Future<void> open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }
  Future<GithubInfo> getInfo(String repo, String id) => info.putIfAbsent(id, () => GithubApi.inspect(repo, projectId: id));
  Future<void> showUpdateCenter(List<Project> catalog) async {
    final available = catalog.where((p) => p.repo != null).toList();
    // A fresh opening rechecks installed versions once per project.
    installedVersionChecks.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(children: [
                Icon(Icons.system_update_alt_rounded,
                  color: Color(0xFF9CC6FF), size: 27),
                SizedBox(width: 12),
                Expanded(child: Text('Обновления приложений',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text('Проверяем опубликованные версии и сравниваем с установленными. '
                'Установка доступна из карточки проекта.',
                style: TextStyle(color: Color(0xFFAABDD9))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: Text('Подключено проектов: ${available.length}',
                  style: const TextStyle(color: Color(0xFFB4C9E6),
                    fontWeight: FontWeight.w600))),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    refresh();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Проверить снова')),
              ]),
            ),
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: available.length,
              itemBuilder: (context, index) {
                final project = available[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: FutureBuilder<GithubInfo>(
                      future: getInfo(project.repo!, project.id),
                      builder: (context, release) => FutureBuilder<String?>(
                        future: cachedInstalledVersion(project.id),
                        builder: (context, installed) {
                          final data = release.data;
                          final comparison = data?.version != null &&
                                  installed.data != null
                            ? comparePublishedVersions(installed.data!, data!.version!)
                            : null;
                          final status = release.hasError ? 'Ошибка проверки релиза'
                            : !release.hasData || !installed.hasData &&
                                installed.connectionState != ConnectionState.done
                              ? 'Проверяем версии…'
                            : data?.downloadUrl == null
                              ? 'Нет установочного файла для устройства'
                            : comparison == -1 ? 'Доступно обновление'
                            : comparison == 0 ? 'Актуальная версия'
                            : comparison == 1 ? 'Установлена более новая версия'
                            : 'Доступна установка';
                          return Row(children: [
                            Icon(comparison == -1
                              ? Icons.new_releases_rounded
                              : comparison == 0 ? Icons.check_circle_outline
                              : Icons.apps_rounded,
                              color: comparison == -1
                                ? const Color(0xFF8DE0C0)
                                : const Color(0xFF9CC6FF)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(project.name, maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(status, style: const TextStyle(
                                  color: Color(0xFFAABDD9), fontSize: 12)),
                                if (data?.version != null)
                                  Text('Релиз: ${data!.version}',
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            )),
                            if (data?.downloadUrl != null &&
                                comparison != 0 && comparison != 1 &&
                                Platform.isAndroid &&
                                Uri.tryParse(data!.downloadUrl!)?.path.toLowerCase().endsWith('.apk') == true)
                              IconButton.filledTonal(
                                tooltip: comparison == -1 ? 'Обновить APK' : 'Установить APK',
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  try {
                                    if (!await confirmExternalInstall(project)) return;
                                    await ProjectLauncher.runInstallExclusive(
                                      project.id,
                                      () => ProjectLauncher.installAndroidApk(
                                        data.downloadUrl!,
                                        projectId: project.id,
                                        externalRepo: project.id.startsWith('external-')
                                          ? project.repo : null,
                                        sha256Digest: data.sha256Digest));
                                    if (mounted) setState(() {});
                                  } catch (error) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Не удалось установить: $error')));
                                    }
                                  }
                                },
                                icon: const Icon(Icons.system_update_alt_rounded))
                            else if (data?.downloadUrl != null &&
                                comparison != 0 && comparison != 1 &&
                                Platform.isWindows && project.id != 'all-hub' &&
                                (Uri.tryParse(data!.downloadUrl!)?.path.toLowerCase().endsWith('.exe') == true ||
                                 Uri.tryParse(data.downloadUrl!)?.path.toLowerCase().endsWith('.zip') == true))
                              IconButton.filledTonal(
                                tooltip: comparison == -1 ? 'Обновить Windows-приложение'
                                  : 'Установить Windows-приложение',
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  try {
                                    if (!await confirmExternalInstall(project)) return;
                                    await ProjectLauncher.updateAndLaunchWindows(
                                      project.id, data.downloadUrl!,
                                      version: data.version,
                                      externalRepo: project.id.startsWith('external-')
                                        ? project.repo : null,
                                      sha256Digest: data.sha256Digest);
                                    installedVersionChecks.remove(project.id);
                                    if (mounted) {
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text(
                                          'Приложение установлено и запущено')));
                                    }
                                  } catch (error) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Ошибка установки: $error')));
                                    }
                                  }
                                },
                                icon: const Icon(Icons.system_update_alt_rounded))
                            else
                              IconButton(
                                tooltip: 'Открыть карточку проекта',
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  setState(() {
                                    tab = 0;
                                    search = project.name;
                                    searchController.text = project.name;
                                    selectedProjectId = project.id;
                                    category = 'All';
                                    showOnlyAvailable = false;
                                  });
                                },
                                icon: const Icon(Icons.chevron_right_rounded)),
                          ]);
                        },
                      ),
                    ),
                  ),
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> refresh() async {
    setState(() { info.clear(); installedVersionChecks.clear(); projects = _loadProjects(); });
    await projects;
    CoverSettings.revision.value++;
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        const Text('Оформление', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.light, label: Text('Светлая'), icon: Icon(Icons.light_mode_outlined)),
            ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная'), icon: Icon(Icons.dark_mode_outlined)),
            ButtonSegment(value: ThemeMode.system, label: Text('Система'), icon: Icon(Icons.settings_brightness_rounded)),
          ],
          selected: {_ThemeControls.of(context).mode},
          onSelectionChanged: (value) => _ThemeControls.of(context).onChanged(value.first),
        ),
        const Divider(height: 30),
        const ListTile(leading: Icon(Icons.sync), title: Text('Общий каталог Android и Windows'),
          subtitle: Text('Каталог обновляется из GitHub, файлы загрузки выбираются под платформу.')),
        if (Platform.isWindows || Platform.isAndroid) ...[
          ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
            builder: (context, revision, child) => ListTile(title: Text(Platform.isAndroid ? 'Импортированные изображения' : 'Папка изображений'),
              subtitle: Text(CoverSettings.folder ?? 'Не выбрана'))),
          FilledButton(onPressed: () async { await CoverSettings.chooseFolder(); },
            child: Text(Platform.isAndroid ? 'Добавить изображения' : 'Выбрать / переназначить папку')),
          OutlinedButton(onPressed: () async { await CoverSettings.clear(); },
            child: Text(Platform.isAndroid ? 'Не использовать импортированные фото' : 'Сбросить папку')),
        ],
        ValueListenableBuilder<int>(valueListenable: CoverSettings.revision,
          builder: (context, revision, child) => SwitchListTile(
            title: const Text('Обложки 18+ (футанари)'),
            subtitle: const Text('Поиск по тегам Danbooru для взрослых персонажей. Может содержать откровенные изображения. Локальные фото имеют приоритет.'),
            value: CoverSettings.adultCovers,
            onChanged: (enabled) => CoverSettings.setAdultCovers(enabled))),
        ValueListenableBuilder<int>(valueListenable: CoverSettings.statusRevision,
          builder: (context, revision, child) => ExpansionTile(
            title: const Text('Диагностика интернет-обложек'),
            subtitle: Text(CoverSettings.errors.isEmpty
              ? 'Ошибок поиска пока нет'
              : 'Проблемы: ${CoverSettings.errors.length}'),
            children: CoverSettings.errors.entries.map((entry) =>
              ListTile(title: Text(entry.key), subtitle: Text(entry.value))).toList(),
          )),
        const ListTile(title: Text('All Hub 0.6.0'),
          subtitle: Text('Общий каталог и загрузки APK / Windows')),
        ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: 58, title: const Row(children: [HubAvatar(size: 32), SizedBox(width: 10), Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2))])),
    body: tab == 5 ? const SnapshotPackCreatorPage() : tab == 1 ? const DevelopmentCenter() : tab == 2 ? const AiModelsPage() : tab == 3 ? const MediaSearchPage() : tab == 4 ? _settings() :
      FutureBuilder<List<Project>>(future: projects, builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Ошибка каталога: ${snap.error}'));
      if (!snap.hasData) return const Center(child: HubWaitIndicator());
      final items = snap.data!;

      final filtered = items.where((p) => (!showOnlyAvailable || p.repo != null) && (category == 'All' || p.type.toLowerCase().contains(category.toLowerCase())) && (search.isEmpty || ('${p.name} ${p.description}').toLowerCase().contains(search.toLowerCase()))).toList();
      return RefreshIndicator(onRefresh: refresh, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        // Project artwork is the hero; avoid an oversized decorative banner.
        if (tab == 0) ...[
          Row(children: [
            Expanded(child: Text('Мои проекты',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: 'Центр обновлений',
              onPressed: () => showUpdateCenter(items),
              icon: const Icon(Icons.system_update_alt_rounded)),
            IconButton(
              tooltip: 'Настройки каталога',
              onPressed: () => setState(() =>
                showCatalogTools = !showCatalogTools),
              icon: Icon(showCatalogTools ? Icons.close_rounded
                : Icons.tune_rounded)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: searchController, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск проектов', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v)),
          if (showCatalogTools) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: addRepository,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить проект'),
            )),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) => SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Align(alignment: Alignment.centerLeft,
                      child: Text('Управление каталогом',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.copy_all_outlined),
                      title: const Text('Экспорт каталога'),
                      subtitle: const Text('Скопировать резервную копию'),
                      onTap: () { Navigator.pop(sheetContext); copyRepositoryBackup(); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.restore_outlined),
                      title: const Text('Восстановить каталог'),
                      subtitle: const Text('Заменить текущий список из копии'),
                      onTap: () { Navigator.pop(sheetContext); importRepositoryBackup(); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.library_add_outlined),
                      title: const Text('Объединить каталоги'),
                      subtitle: const Text('Добавить проекты из резервной копии'),
                      onTap: () { Navigator.pop(sheetContext); importRepositoryBackup(merge: true); },
                    ),
                  ]),
                )),
              ),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Каталог'),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in ['All', 'game', 'app', 'mod'])
              ChoiceChip(
                label: Text(c == 'All' ? 'Все' : c == 'game' ? 'Игры'
                  : c == 'app' ? 'Приложения' : 'Моды'),
                selected: category == c,
                onSelected: (_) => setState(() => category = c)),
            FilterChip(
              avatar: const Icon(Icons.cloud_done_outlined, size: 18),
              label: const Text('С GitHub'),
              selected: showOnlyAvailable,
              onSelected: (enabled) =>
                setState(() => showOnlyAvailable = enabled)),
          ]),
          ],
          const SizedBox(height: 16),
        ],
        if (tab != 0) Row(children: [Expanded(child: Text('Состояние сборок', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))), Text('${(tab == 0 ? filtered : items).length} ПРОЕКТА', style: const TextStyle(color: hubAccent, fontSize: 11, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 12),
        if (tab == 0 && filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
            decoration: BoxDecoration(
              color: const Color(0xFF15243B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2A405E))),
            child: Column(children: [
              const Icon(Icons.search_off_rounded, size: 42,
                color: Color(0xFF89B4E9)),
              const SizedBox(height: 12),
              Text('Проекты не найдены',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Измени поиск или сбрось фильтры',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFAFC2DC))),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  search = '';
                  searchController.clear();
                  category = 'All';
                  showOnlyAvailable = false;
                }),
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Сбросить фильтры')),
            ]),
          ),
        if (tab == 0 && filtered.isNotEmpty) ...[
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 920 ? 5
                : constraints.maxWidth >= 600 ? 4 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.73,
              ),
              itemBuilder: (context, index) {
                final project = filtered[index];
                final selected = selectedProjectId == project.id;
                return Material(
                  color: const Color(0xFF101B2D),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() =>
                      selectedProjectId = selected ? null : project.id),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected ? const Color(0xFF7AAEFF)
                            : const Color(0xFF263C57),
                          width: selected ? 2 : 1),
                        borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        Expanded(child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                          child: SizedBox(
                            width: double.infinity,
                            child: ProjectCover(
                              id: project.id,
                              title: project.name,
                              type: project.type),
                          ),
                        )),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(project.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                              if (selected) ...[
                                const SizedBox(height: 5),
                                Text(project.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11)),
                                const SizedBox(height: 5),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ProjectDetailPage(
                                        project: project))),
                                  child: const Text('О проекте'),
                                ),
                              ] else
                                const Text('Нажми для описания',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            );
          }),
          const SizedBox(height: 12),
          if (selectedProjectId == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Нажми на обложку, чтобы увидеть краткое описание.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFA9BED9))),
            ),
        ],
        for (final project in (tab == 0
          ? <Project>[]
          : items)) Card(margin: const EdgeInsets.only(bottom: 14), clipBehavior: Clip.antiAlias, child: Column(children: [
          if (project.id.startsWith('external-'))
            FutureBuilder<String?>(
              future: ExternalArtwork.load(project.id),
              builder: (context, artwork) => HubProjectHeader(
                title: project.name, type: project.type, repo: project.repo,
                localBannerPath: artwork.data))
          else
            ProjectCover(id: project.id, title: project.name, type: project.type),
          Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1D3659),
                  borderRadius: BorderRadius.circular(13)),
                child: Icon(
                  project.type.toLowerCase().contains('game') ? Icons.sports_esports_rounded
                    : project.type.toLowerCase().contains('mod') ? Icons.extension_rounded
                    : Icons.apps_rounded,
                  color: const Color(0xFF9CC6FF), size: 23)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(project.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(project.type == 'Android game' ? 'Игра для Android'
                  : project.type == 'Android app' ? 'Приложение для Android'
                  : project.type.toLowerCase().contains('mod') ? 'Мод Minecraft'
                  : project.type,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF9BB7DC))),
              ])),
              const SizedBox(width: 6),
              Tooltip(
                message: project.repo == null
                  ? 'Репозиторий не подключён' : 'Репозиторий подключён',
                child: Icon(
                  project.repo == null ? Icons.link_off_rounded : Icons.link_rounded,
                  size: 19,
                  color: project.repo == null
                    ? const Color(0xFF8390A5) : const Color(0xFF7DCEAC))),
            ]),
            const SizedBox(height: 12),
            Text(project.description, maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.4, color: const Color(0xFFCDD6E6))),
            if (project.id.startsWith('external-'))
              ExternalScreenshotGallery(projectId: project.id),
            if (project.id.startsWith('external-'))
              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                onPressed: () => chooseExternalArtwork(project),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Своя обложка (локально)'))),
            if (project.id.startsWith('external-'))
              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                onPressed: () => removeRepository(project),
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Убрать из каталога'))),
            if (Platform.isAndroid && project.id.startsWith('external-'))
              Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
                onPressed: () => configureExternalPackage(project),
                icon: const Icon(Icons.app_registration_outlined),
                label: const Text('Указать package ID для запуска'))),
            if (project.id == 'kopilka') Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Открыть Копилку'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const KopilkaPage())),
              ),
            ),
            if (project.repo == null) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Репозиторий пока не подключён'))
            else FutureBuilder<GithubInfo>(future: getInfo(project.repo!, project.id), builder: (context, s) {
              if (!s.hasData) return const Center(child: Padding(padding: EdgeInsets.all(12), child: HubWaitIndicator(size: 46)));
              final i = s.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: i.downloadUrl != null
                      ? const Color(0xFF183A39) : const Color(0xFF242D42),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: i.downloadUrl != null
                      ? const Color(0xFF2E6E65) : const Color(0xFF35445E))),
                  child: Row(children: [
                    Icon(i.downloadUrl != null
                      ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      size: 20, color: i.downloadUrl != null
                        ? const Color(0xFF8DE0C0) : const Color(0xFFB3C0D6)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(i.downloadUrl != null
                      ? 'Установочный файл доступен'
                      : 'Сборка для устройства ещё не опубликована',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  ]),
                ),
                ProjectDownloadProgress(projectId: project.id),
                FutureBuilder<String?>(
                  future: ProjectLauncher.installedVersion(project.id),
                  builder: (context, installed) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Установлено: ${installed.data ?? 'версия неизвестна'}',
                        style: Theme.of(context).textTheme.bodySmall),
                      Text('Опубликовано: ${i.version ?? 'нет релиза'}',
                        style: Theme.of(context).textTheme.bodySmall),
                      Text(i.downloadUrl == null
                        ? 'Обновление для этой платформы пока недоступно'
                        : describeUpdateStatus(installed.data, i.version),
                        style: TextStyle(color: comparePublishedVersions(
                          installed.data ?? '', i.version ?? '') == -1
                          ? Colors.greenAccent : hubAccent)),
                    ]),
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Что нового и диагностика', style: TextStyle(fontSize: 13)),
                  children: [
                    if (i.releaseNotes != null && i.releaseNotes!.isNotEmpty)
                      Align(alignment: Alignment.centerLeft,
                        child: Text('Описание релиза: ${i.releaseNotes}')),
                    if (i.releaseNotes == null || i.releaseNotes!.isEmpty)
                      const Align(alignment: Alignment.centerLeft,
                        child: Text('Список изменений пока не опубликован.')),
                    Align(alignment: Alignment.centerLeft,
                      child: Text('Состояние сборки: ${i.workflowStatus ?? 'нет данных'}')),
                    if (i.error != null)
                      Align(alignment: Alignment.centerLeft, child: Text(i.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.tertiary))),
                  ],
                ),
                if (tab == 0 && project.id != 'all-hub' && ProjectLauncher.canLaunch(project.id))
                  FutureBuilder<bool>(
                    future: ProjectLauncher.isAvailable(project.id),
                    builder: (context, status) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Icon(status.data == true ? Icons.check_circle_outline : Icons.info_outline,
                          size: 16, color: status.data == true ? Colors.greenAccent : Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Expanded(child: Text(status.data == true
                          ? 'Готово к запуску'
                          : Platform.isAndroid ? 'APK не установлен или не обнаружен' : 'EXE ещё не привязан',
                          style: Theme.of(context).textTheme.bodySmall)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => open('https://github.com/${project.repo}'), icon: const Icon(Icons.code), label: const Text('Репозиторий')),
                  if (tab == 0 && i.downloadUrl == null)
                    FilledButton.icon(onPressed: () => open(i.actionsUrl ?? 'https://github.com/${project.repo}/actions'), icon: const Icon(Icons.download), label: const Text('Сборка пока недоступна')),
                  if (tab == 0 && project.id != 'all-hub' && ProjectLauncher.canLaunch(project.id))
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Открыть'),
                      onPressed: () async {
                        try {
                          final ok = await ProjectLauncher.launch(project.id);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Приложение не найдено или не установлено')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка запуска: $e')));
                           }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isAndroid && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.apk'))
                    FutureBuilder<String?>(
                      future: ProjectLauncher.installedVersion(project.id),
                      builder: (context, installed) {
                        final comparison = installed.data == null || i.version == null
                            ? null : comparePublishedVersions(installed.data!, i.version!);
                        // Always expose the Android installer action, including
                        // self-update and same-version repair installs. The
                        // version comparison is advisory, not a reason to hide
                        // the only way to repair a broken installation.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Установлено: ${installed.data ?? "не определено"} · Релиз: ${i.version ?? "не определено"}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFAABDD9))),
                            const SizedBox(height: 6),
                            FilledButton.icon(
                          icon: Icon(comparison == -1 ? Icons.system_update_alt_rounded : Icons.install_mobile_rounded),
                          label: Text(comparison == -1 ? 'Обновить до ${i.version}' :
                            comparison == 0 ? 'Переустановить эту версию' :
                            comparison == 1 ? 'Версия новее — открыть установщик' : 'Скачать и установить'),
                          onPressed: () async {
                            try {
                              if (isPublishedDowngrade(
                                  await ProjectLauncher.installedVersion(project.id), i.version)) {
                                throw StateError('Понижение версии заблокировано');
                              }
                              if (!await confirmExternalInstall(project)) return;
                              await ProjectLauncher.runInstallExclusive(project.id,
                                () => ProjectLauncher.installAndroidApk(i.downloadUrl!,
                                  projectId: project.id,
                                  externalRepo: project.id.startsWith('external-') ? project.repo : null,
                                  sha256Digest: i.sha256Digest));
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка установки APK: $e')));
                              }
                            }
                          },
                            ),
                          ],
                        );
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && project.id == 'all-hub')
                    FutureBuilder<String?>(
                      future: ProjectLauncher.installedVersion('all-hub'),
                      builder: (context, installed) {
                        if (installed.connectionState != ConnectionState.done) {
                          return const Chip(label: Text('Проверяем установленную версию…'));
                        }
                        final current = installed.data;
                        final published = i.version;
                        final comparison = current == null || published == null
                            ? null : comparePublishedVersions(current, published);
                        if (comparison == 0) {
                          return const Chip(avatar: Icon(Icons.check_circle_outline, size: 18),
                            label: Text('All Hub обновлён до актуальной версии'));
                        }
                        if (comparison == 1) {
                          return const Chip(label: Text('Установленная версия новее опубликованной'));
                        }
                        if (i.downloadUrl == null) {
                          return const Chip(label: Text('Windows EXE пока не опубликован'));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Установлено: ${current ?? 'не определено'}  •  Доступно: ${published ?? 'не определено'}'),
                            if (allHubUpdateInProgress)
                              ValueListenableBuilder<double?>(
                                valueListenable: ProjectLauncher.downloadProgress,
                                builder: (context, progress, _) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: HubLiquidProgress(value: progress),
                                ),
                              ),
                            FilledButton.icon(
                              icon: allHubUpdateInProgress
                                  ? const SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.system_update_alt_rounded),
                              label: const Text('Обновить'),
                          onPressed: allHubUpdateInProgress ? null : () async {
                            setState(() => allHubUpdateInProgress = true);
                            try {
                              if (i.version == null) {
                                throw StateError('Не удалось определить версию релиза');
                              }
                              // The updater stages the executable and starts an external
                              // helper; exit only after that handoff succeeds.
                              await ProjectLauncher.updateAllHubWindows(
                                i.downloadUrl!, version: i.version,
                                sha256Digest: i.sha256Digest,
                              );
                              exit(0);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка обновления All Hub: $e')));
                              }
                            } finally {
                              if (mounted) setState(() => allHubUpdateInProgress = false);
                            }
                          },
                            ),
                          ],
                        );
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && project.id != 'all-hub' && i.downloadUrl != null)
                    FutureBuilder<String?>(
                      future: ProjectLauncher.installedVersion(project.id),
                      builder: (context, installed) {
                        final hasInstalledVersion = installed.data != null;
                        final comparison = hasInstalledVersion && i.version != null
                            ? comparePublishedVersions(installed.data!, i.version!)
                            : null;
                        // Always expose the update action on Windows: legacy
                        // installations have no stored version and previously
                        // made the button disappear completely.
                        final isNewerLocal = comparison == 1;
                        return FilledButton.icon(
                          icon: const Icon(Icons.system_update_alt_rounded),
                          label: Text(windowsUpdateActionLabel(installed.data, i.version)),
                          
                          onPressed: isNewerLocal ? null : () async {
                            try {
                              if (!await confirmExternalInstall(project)) return;
                              await ProjectLauncher.updateAndLaunchWindows(
                                project.id, i.downloadUrl!,
                                version: i.version,
                                externalRepo: project.id.startsWith('external-') ? project.repo : null,
                                sha256Digest: i.sha256Digest,
                              );
                              if (context.mounted) setState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Обновление установлено. Новая версия запущена.')));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка обновления: $e')));
                              }
                            }
                          },
                        );
                      },
                    ),
                  if (tab == 1) OutlinedButton(onPressed: () => open('https://github.com/${project.repo}/actions'), child: const Text('Actions')),
                ]),
              ]);
            }),
          ]))])),
      ]));
    }),
    bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
      ValueListenableBuilder<String?>(
        valueListenable: ProjectLauncher.activeDownloadProject,
        builder: (context, active, _) {
          if (active == null) return const SizedBox.shrink();
          return ValueListenableBuilder<double?>(
            valueListenable: ProjectLauncher.downloadProgress,
            builder: (context, value, _) {
              final safe = value != null && value.isFinite
                ? value.clamp(0.0, 1.0).toDouble() : null;
              return Material(
                color: const Color(0xFF162D4D),
                child: InkWell(
                  onTap: () => setState(() => tab = 0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Column(children: [
                      Row(children: [
                        const Icon(Icons.downloading_rounded,
                          color: Color(0xFF8DC7FF), size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          'Загрузка: ${active == 'all-hub' ? 'All Hub' : active}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text(safe == null ? 'Подготовка…'
                          : '${(safe * 100).round()}%',
                          style: const TextStyle(color: Color(0xFFB5D5FF))),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right_rounded, size: 19),
                      ]),
                      const SizedBox(height: 7),
                      HubLiquidProgress(
                        value: safe, height: 7,
                        ),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
      LayoutBuilder(builder: (context, constraints) {
      // Four destinations fit comfortably on narrow phones. Secondary tools
      // remain one tap away without clipped or wrapped navigation labels.
      if (constraints.maxWidth < 620) {
        return NavigationBar(
          height: 70,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: tab == 0 ? 0 : tab == 2 ? 1 : tab == 3 ? 2 : 3,
          onDestinationSelected: (index) {
            if (index < 3) {
              setState(() => tab = [0, 2, 3][index]);
              return;
            }
            showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => SafeArea(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Align(alignment: Alignment.centerLeft,
                      child: Text('Инструменты All Hub',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  ),
                  ListTile(
                    leading: const Icon(Icons.build_circle_outlined),
                    title: const Text('Разработка'),
                    subtitle: const Text('Проекты, сборки и GitHub'),
                    onTap: () { Navigator.pop(sheetContext); setState(() => tab = 1); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Настройки'),
                    subtitle: const Text('Параметры приложения'),
                    onTap: () { Navigator.pop(sheetContext); setState(() => tab = 4); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Snapshot'),
                    subtitle: const Text('Пакеты изображений'),
                    onTap: () { Navigator.pop(sheetContext); setState(() => tab = 5); },
                  ),
                  const SizedBox(height: 12),
                ],
              )),
            );
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Проекты'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_rounded), label: 'Эйра'),
            NavigationDestination(icon: Icon(Icons.perm_media_outlined), label: 'Медиа'),
            NavigationDestination(icon: Icon(Icons.widgets_outlined), label: 'Ещё'),
          ],
        );
      }
      return NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Проекты'),
          NavigationDestination(icon: Icon(Icons.build_circle_outlined), label: 'Разработка'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_rounded), label: 'Эйра'),
          NavigationDestination(icon: Icon(Icons.perm_media_outlined), label: 'Медиа'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), label: 'Snapshot'),
        ],
      );
      }),
    ]),
  );
}
