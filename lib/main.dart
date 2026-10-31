import 'project_launcher.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const AllHub());

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
    final available = result.assets.where((a) {
      if (a.platform != currentPlatform) return false;
      final name = a.name.toLowerCase();
      if (projectId == 'kopilka') return name.startsWith('kopilka-');
      if (projectId == 'all-hub') return name.startsWith('allhub-') || name.startsWith('all-hub-');
      return true;
    }).toList();
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

class AllHub extends StatelessWidget {
  const AllHub({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'All Hub', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: hubPurple, brightness: Brightness.dark),
      scaffoldBackgroundColor: hubBackground,
      cardTheme: CardThemeData(color: hubPanel, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFF263956)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF15223A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none)),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF101B30), indicatorColor: Color(0xFF234A88)),
      appBarTheme: const AppBarTheme(backgroundColor: hubBackground,
        centerTitle: false, surfaceTintColor: Colors.transparent)),
    home: const HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  String category = 'All';
  String search = '';
  bool showOnlyAvailable = false;
  late Future<List<Project>> projects = _loadProjects();
  @override
  void initState() {
    super.initState();
    CoverSettings.load();
    migrateAllHubMedia();
  }
  final Map<String, Future<GithubInfo>> info = {};
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

  Future<void> importRepositoryBackup() async {
    final clipboard = await Clipboard.getData('text/plain');
    if (!mounted) {
      return;
    }
    final controller = TextEditingController(text: clipboard?.text ?? '');
    final source = await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт публичных репозиториев'),
        content: SizedBox(width: 540, child: TextField(
          controller: controller, maxLines: 8, minLines: 4,
          decoration: const InputDecoration(
            hintText: 'Вставь JSON-каталог All Hub',
            helperText: 'Импорт заменит только список сторонних репозиториев.'),
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
          title: const Text('Заменить каталог?'),
          content: Text('Будут проверены ${parsed.length} публичных '
            'GitHub-репозиториев. Текущий список будет заменён только '
            'после успешной проверки всех адресов. '
            'Установленные приложения и их данные останутся без изменений.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Проверить и импортировать')),
          ],
        ));
      if (approved != true || !mounted) {
        return;
      }
      final count = await ExternalRepositoryStore.importBackup(source);
      if (!mounted) {
        return;
      }
      await refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Импортировано репозиториев: $count')));
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
  Future<void> refresh() async {
    setState(() { info.clear(); projects = _loadProjects(); });
    await projects;
    CoverSettings.revision.value++;
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
  Widget _mobileShortcut(IconData icon, String label, VoidCallback action) =>
    OutlinedButton(
      onPressed: action,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: Color(0xFF244B85)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: hubAccent, size: 22),
        const SizedBox(height: 5),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
      ]),
    );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [HubAvatar(size: 32), SizedBox(width: 10), Text('ALL HUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2))]), actions: [IconButton(tooltip: 'Обновить каталог', onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
    body: tab == 1 ? const DevelopmentCenter() : tab == 2 ? const AiModelsPage() : tab == 3 ? const MediaSearchPage() : tab == 4 ? _settings() :
      FutureBuilder<List<Project>>(future: projects, builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Ошибка каталога: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;

      final filtered = items.where((p) => (!showOnlyAvailable || p.repo != null) && (category == 'All' || p.type.toLowerCase().contains(category.toLowerCase())) && (search.isEmpty || ('${p.name} ${p.description}').toLowerCase().contains(search.toLowerCase()))).toList();
      return RefreshIndicator(onRefresh: refresh, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        if (tab == 0) ...[const HubBanner(), const SizedBox(height: 20)],
        if (tab == 0) ...[
          TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск проектов', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: addRepository, icon: const Icon(Icons.add_link),
            label: const Text('Добавить приложение из GitHub')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: copyRepositoryBackup,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Копировать каталог')),
            OutlinedButton.icon(onPressed: importRepositoryBackup,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Импорт каталога')),
          ]),
          const SizedBox(height: 12),
          if (Platform.isAndroid) ...[
            Row(children: [
              Expanded(child: _mobileShortcut(Icons.apps_rounded, 'Проекты', () => setState(() { category = 'All'; search = ''; }))),
              const SizedBox(width: 8),
              Expanded(child: _mobileShortcut(Icons.photo_library_outlined, 'Медиа', () => setState(() => tab = 3))),
              const SizedBox(width: 8),
              Expanded(child: _mobileShortcut(Icons.smart_toy_outlined, 'ИИ', () => setState(() => tab = 2))),
              const SizedBox(width: 8),
              Expanded(child: _mobileShortcut(Icons.settings_outlined, 'Настройки', () => setState(() => tab = 4))),
            ]),
            const SizedBox(height: 14),
          ],
          Wrap(spacing: 8, children: [for (final c in ['All', 'game', 'app', 'mod']) ChoiceChip(label: Text(c == 'All' ? 'Все' : c == 'game' ? 'Игры' : c == 'app' ? 'Приложения' : 'Моды'), selected: category == c, onSelected: (_) => setState(() => category = c))]),
          const SizedBox(height: 16),
        ],
        Row(children: [Expanded(child: Text(tab == 0 ? 'Мои проекты' : 'Состояние сборок', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))), Text('${(tab == 0 ? filtered : items).length} ПРОЕКТА', style: const TextStyle(color: hubAccent, fontSize: 11, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 16),
        for (final project in (tab == 0 ? filtered : items)) Card(margin: const EdgeInsets.only(bottom: 14), clipBehavior: Clip.antiAlias, child: Column(children: [
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
            Row(children: [const Icon(Icons.widgets_outlined, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(project.name, style: Theme.of(context).textTheme.titleLarge),
              Text(project.type == 'Android game' ? 'Игра для Android' : project.type == 'Android app' ? 'Приложение для Android' : project.type.toLowerCase().contains('mod') ? 'Мод Minecraft' : project.type, style: Theme.of(context).textTheme.bodySmall),
            ]))]),
            const SizedBox(height: 8), Text(project.description),
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
              if (!s.hasData) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              final i = s.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.system_update_alt_rounded, size: 17, color: hubAccent),
                  const SizedBox(width: 7),
                  Expanded(child: Text(i.downloadUrl != null
                    ? 'Опубликован установочный файл'
                    : 'Файл для этой платформы не опубликован',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
                if (project.id == ProjectLauncher.activeDownloadProject.value)
                  ValueListenableBuilder<double?>(
                    valueListenable: ProjectLauncher.downloadProgress,
                    builder: (context, progress, child) => progress == null
                      ? const SizedBox.shrink()
                      : Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Загрузка: ${(progress * 100).toStringAsFixed(0)}%'),
                            LinearProgressIndicator(value: progress),
                          ]))),
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
                if (tab == 0 && ProjectLauncher.canLaunch(project.id))
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
                  if (tab == 0 && ProjectLauncher.canLaunch(project.id))
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Открыть'),
                      onPressed: () async {
                        try {
                          final ok = await ProjectLauncher.launch(project.id);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Приложение не найдено или EXE не выбран')));
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
                    OutlinedButton.icon(
                      icon: const Icon(Icons.install_mobile),
                      label: FutureBuilder<String?>(
                        future: ProjectLauncher.installedVersion(project.id),
                        builder: (context, installed) => Text(installActionLabel(
                          installed.data, i.version, 'Скачать APK и установить')),
                      ),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачивание APK...')));
                        try {
                          if (isPublishedDowngrade(
                              await ProjectLauncher.installedVersion(project.id), i.version)) {
                            throw StateError('Установленная версия новее опубликованной. Понижение версии заблокировано.');
                          }
                          if (!await confirmExternalInstall(project)) {
                            return;
                          }
                          await ProjectLauncher.installAndroidApk(i.downloadUrl!,
                            projectId: project.id,
                            externalRepo: project.id.startsWith('external-')
                                ? project.repo : null,
                            sha256Digest: i.sha256Digest);
                        } catch (e) {
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка установки APK: $e')));
                           }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.exe'))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.install_desktop),
                      label: FutureBuilder<String?>(
                        future: ProjectLauncher.installedVersion(project.id),
                        builder: (context, installed) => Text(installActionLabel(
                          installed.data, i.version, 'Скачать и установить')),
                      ),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачивание EXE из GitHub Releases...')));
                        try {
                          if (isPublishedDowngrade(
                              await ProjectLauncher.installedVersion(project.id), i.version)) {
                            throw StateError('Установленная версия новее опубликованной. Понижение версии заблокировано.');
                          }
                          if (!await confirmExternalInstall(project)) {
                            return;
                          }
                          await ProjectLauncher.installWindowsExe(project.id, i.downloadUrl!,
                            externalRepo: project.id.startsWith('external-')
                                ? project.repo : null,
                            sha256Digest: i.sha256Digest);
                          await ProjectLauncher.recordInstalledVersion(project.id, i.version);
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EXE установлен и привязан. Нажми «Открыть».')));
                           }
                        } catch (e) {
                          if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось установить EXE: $e')));
                           }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows && i.downloadUrl != null &&
                      Uri.parse(i.downloadUrl!).path.toLowerCase().endsWith('.zip'))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: FutureBuilder<String?>(
                        future: ProjectLauncher.installedVersion(project.id),
                        builder: (context, installed) => Text(installActionLabel(
                          installed.data, i.version, 'Скачать и установить')),
                      ),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скачиваем игру со всеми файлами...')));
                        try {
                          if (isPublishedDowngrade(
                              await ProjectLauncher.installedVersion(project.id), i.version)) {
                            throw StateError('Установленная версия новее опубликованной. Понижение версии заблокировано.');
                          }
                          if (!await confirmExternalInstall(project)) {
                            return;
                          }
                          await ProjectLauncher.installWindowsZip(project.id, i.downloadUrl!,
                            externalRepo: project.id.startsWith('external-')
                                ? project.repo : null,
                            sha256Digest: i.sha256Digest);
                          await ProjectLauncher.recordInstalledVersion(project.id, i.version);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Игра установлена. Нажми «Открыть».')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка установки: $e')));
                          }
                        }
                      },
                    ),
                  if (tab == 0 && Platform.isWindows)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выбрать EXE'),
                      onPressed: () async {
                        final ok = await ProjectLauncher.configureWindowsExecutable(project.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? 'EXE привязан' : 'EXE не выбран')));
                        }
                      },
                    ),
                  if (tab == 1) OutlinedButton(onPressed: () => open('https://github.com/${project.repo}/actions'), child: const Text('Actions')),
                ]),
              ]);
            }),
          ]))])),
      ]));
    }),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.grid_view), label: 'Проекты'),
      NavigationDestination(icon: Icon(Icons.build_circle_outlined), label: 'Разработка'),
      NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'ИИ'),
      NavigationDestination(icon: Icon(Icons.travel_explore), label: 'Медиа'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
    ]),
  );
}
