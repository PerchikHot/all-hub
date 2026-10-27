import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// Pick a local image directory on Windows or Android where supported by the platform.
/// No local images are uploaded. Unsupported directory access falls back to remote covers.
class CoverSettings {
  static String? folder;
  static bool adultCovers = false;
  static final Map<String, List<String>> cache = {};
  static final Map<String, DateTime> cacheAt = {};
  static final Map<String, String> errors = {};
  static final ValueNotifier<int> statusRevision = ValueNotifier<int>(0);
  static final Map<String, Future<List<String>>> pending = {};
  static Future<void> setAdultCovers(bool enabled) async {
    adultCovers = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('adult_covers', enabled);
    revision.value++;
  }
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    folder = prefs.getString('desktop_cover_folder');
    adultCovers = prefs.getBool('adult_covers') ?? false;
    revision.value++;
  }
  static Future<bool> chooseFolder() async {
    if (!Platform.isWindows && !Platform.isAndroid) return false;
    String? selected;
    if (Platform.isAndroid) return importImages();
    try {
      selected = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Папка с обложками All Hub');
    } catch (_) {
      return false;
    }
    if (selected == null) return false;
    folder = selected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('desktop_cover_folder', selected);
    revision.value++;
    return true;
  }
  static Future<bool> importImages() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: false);
    if (picked == null || picked.files.isEmpty) return false;
    final base = await getApplicationSupportDirectory();
    final imported = Directory('${base.path}/all_hub_covers');
    await imported.create(recursive: true);
    var count = 0;
    for (final item in picked.files) {
      if (item.path == null) continue;
      final ext = item.extension?.toLowerCase() ?? 'jpg';
      if (!['png','jpg','jpeg','webp','bmp'].contains(ext)) continue;
      try {
        await File(item.path!).copy('${imported.path}/cover_${DateTime.now().microsecondsSinceEpoch}_$count.$ext');
        count++;
      } catch (_) {}
    }
    if (count == 0) return false;
    folder = imported.path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('desktop_cover_folder', folder!);
    revision.value++;
    return true;
  }
  static Future<void> clear() async {
    folder = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('desktop_cover_folder');
    revision.value++;
  }
}

class ProjectCover extends StatefulWidget {
  final String id, title, type;
  const ProjectCover({super.key, required this.id, required this.title, required this.type});
  @override
  State<ProjectCover> createState() => _ProjectCoverState();
}

class _ProjectCoverState extends State<ProjectCover> {
  File? localFile;
  List<String> webCovers = [];
  int webIndex = 0;
  bool loadingWeb = false;
  bool reloadQueued = false;
  int generation = 0;
  List<File> localCandidates = [];
  final Set<String> failedImages = {};
  String? scannedFolder;
  Timer? rotationTimer;
  @override
  void initState() {
    super.initState();
    CoverSettings.revision.addListener(onSettingsChanged);
    refresh();
    loadWebCovers();
    rotationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (localCandidates.isNotEmpty) {
        final alternatives = localCandidates.where((f) => f.path != localFile?.path).toList();
        final candidates = alternatives.isNotEmpty ? alternatives : localCandidates;
        setState(() => localFile = candidates[Random().nextInt(candidates.length)]);
      } else if (webCovers.isNotEmpty) {
        final next = List.generate(webCovers.length, (i) => (webIndex + i + 1) % webCovers.length)
          .where((i) => !failedImages.contains(webCovers[i]));
        if (next.isNotEmpty) setState(() => webIndex = next.first);
      }
    });
  }
  @override
  void didUpdateWidget(covariant ProjectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) { onSettingsChanged(); }
  }
  @override
  void dispose() {
    rotationTimer?.cancel();
    CoverSettings.revision.removeListener(onSettingsChanged);
    super.dispose();
  }
  // Danbooru tag search: general-rated art by default, explicit only by opt-in.
  void onSettingsChanged() {
    // Never display images from the previous content mode while fetching replacements.
    setState(() { webCovers = []; webIndex = 0; failedImages.clear(); });
    refresh();
    if (loadingWeb) { reloadQueued = true; return; }
    loadWebCovers();
  }
  Future<void> loadWebCovers() async {
    if (loadingWeb) return;
    loadingWeb = true;
    final adult = CoverSettings.adultCovers && widget.id != 'kopilka';
    final id = widget.id;
    final cacheKey = '$id:$adult';
    final saved = CoverSettings.cache[cacheKey];
    if (saved != null && saved.isNotEmpty && DateTime.now().difference(CoverSettings.cacheAt[cacheKey] ?? DateTime(2000)).inMinutes < 30) {
      if (mounted && CoverSettings.adultCovers == adult && widget.id == id) setState(() { webCovers = saved; webIndex = 0; failedImages.clear(); });
      loadingWeb = false;
      return;
    }
    final queries = <String, String>{
      'all-hub': 'alpha_(kage_no_jitsuryokusha_ni_naritakute!) rating:general',
      'eclipse-arena': 'erza_scarlet rating:general',
      'shadow-rp': 'rias_gremory rating:general',
      'shadow-garden': 'delta_(kage_no_jitsuryokusha_ni_naritakute!) rating:general',
      'kopilka': 'original rating:general',
    };
    final search = queries[id] ?? 'original rating:general';
    try {
      if (adult) {
        // Only adult-character searches; reject posts marked as young characters.
        final tags = <String, String>{
          'eclipse-arena': 'erza_scarlet futanari',
          'shadow-rp': 'boa_hancock futanari',
          'shadow-garden': 'futanari rating:explicit',
          'all-hub': 'alpha_(kage_no_jitsuryokusha_ni_naritakute!) futanari',
          'kopilka': 'original rating:general',
        };
        final uri = Uri.https('danbooru.donmai.us', '/posts.json', {
          'tags': tags[id] ?? tags['all-hub']!, 'limit':'20',
        });
        final response = await http.get(uri, headers: {'User-Agent':'AllHub/0.5 (cover viewer)'}).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          CoverSettings.errors[id] = 'Danbooru: HTTP ${response.statusCode}';
          CoverSettings.statusRevision.value++;
          return;
        }
        final posts = jsonDecode(response.body) as List<dynamic>;
        final urls = <String>[];
        for (final post in posts) {
          final item = post as Map<String, dynamic>;
          if (item['rating']?.toString() != 'e') continue;
          final tags = (item['tag_string'] ?? '').toString().toLowerCase();
          if (RegExp(r'(^|\\s)(loli|shota|child|underage)(\\s|$)').hasMatch(tags)) continue;
          final url = item['large_file_url']?.toString() ?? item['file_url']?.toString() ?? item['preview_file_url']?.toString();
          if (url != null && url.startsWith('https://')) urls.add(url);
        }
        if (urls.isNotEmpty) { CoverSettings.cache[cacheKey] = urls; CoverSettings.cacheAt[cacheKey] = DateTime.now(); CoverSettings.errors.remove(id); }
        else { CoverSettings.errors[id] = 'Поиск не вернул подходящих изображений'; }
        CoverSettings.statusRevision.value++;
        if (mounted && widget.id == id && CoverSettings.adultCovers == adult) setState(() { webCovers = urls; webIndex = 0; failedImages.clear(); });
        return;
      }
      final uri = Uri.https('danbooru.donmai.us', '/posts.json', {
        'tags': search, 'limit': '30',
      });
      final response = await http.get(uri, headers: {'User-Agent':'AllHub/0.5 (cover viewer)'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        CoverSettings.errors[id] = 'Danbooru: HTTP ${response.statusCode}';
        CoverSettings.statusRevision.value++;
        return;
      }
      final posts = jsonDecode(response.body) as List<dynamic>;
      final urls = <String>[];
      for (final post in posts) {
        final item = post as Map<String, dynamic>;
        if (item['rating']?.toString() != 'g') continue;
        final url = item['preview_file_url']?.toString() ??
            item['large_file_url']?.toString() ?? item['file_url']?.toString();
        if (url != null && url.startsWith('https://')) urls.add(url);
      }
      if (urls.isNotEmpty) {
        CoverSettings.cache[cacheKey] = urls;
        CoverSettings.cacheAt[cacheKey] = DateTime.now();
        CoverSettings.errors.remove(id);
      } else {
        CoverSettings.errors[id] = 'Поиск не вернул подходящих изображений';
      }
      CoverSettings.statusRevision.value++;
      if (mounted && widget.id == id && CoverSettings.adultCovers == adult) {
        setState(() { webCovers = urls; webIndex = 0; });
      }
    } catch (e) {
      CoverSettings.errors[id] = 'Ошибка поиска: $e';
      CoverSettings.statusRevision.value++;
      // Offline or API unavailable: retain local image / gradient fallback.
    } finally {
      loadingWeb = false;
      if (reloadQueued && mounted) {
        reloadQueued = false;
        loadWebCovers();
      }
    }
  }
  Future<void> refresh() async {
    final current = ++generation;
    File? selected;
    final folder = CoverSettings.folder;
    if ((Platform.isWindows || Platform.isAndroid) && folder != null) {
      try {
        if (scannedFolder != folder) { localCandidates = []; scannedFolder = folder; }
        final dir = Directory(folder);
        if (await dir.exists()) {
          final files = await dir.list(followLinks: false).where((entry) =>
            entry is File && RegExp(r'\.(png|jpg|jpeg|webp|bmp)$', caseSensitive: false).hasMatch(entry.path)
          ).cast<File>().toList();
          final matching = files.where((f) => f.path.toLowerCase().split(Platform.pathSeparator).last.startsWith('${widget.id.toLowerCase()}_')).toList();
          // Imported cover files have generic names. Give each project a stable
          // subset rather than repeating the same random cover everywhere.
          files.sort((a, b) => a.path.compareTo(b.path));
          const projectIds = ['all-hub', 'eclipse-arena', 'shadow-rp', 'shadow-garden', 'kopilka'];
          final projectIndex = projectIds.indexOf(widget.id);
          final shared = projectIndex < 0 ? files : <File>[
            for (var i = 0; i < files.length; i++)
              if (i % projectIds.length == projectIndex) files[i],
          ];
          // Explicit project-prefixed filenames always take precedence.
          localCandidates = matching.isNotEmpty ? matching : shared;
          if (localCandidates.isNotEmpty) {
            final alternatives = localCandidates.where((f) => f.path != localFile?.path).toList();
            final candidates = alternatives.isNotEmpty ? alternatives : localCandidates;
            selected = candidates[Random().nextInt(candidates.length)];
          }
        }
      } catch (_) { /* Inaccessible directory: show built-in fallback. */ }
    }
    if (folder == null) { localCandidates = []; scannedFolder = null; }
    if (mounted && current == generation) setState(() => localFile = selected);
  }
  @override
  Widget build(BuildContext context) {
    final isGame = widget.type.toLowerCase().contains('game');
    final isMod = widget.type.toLowerCase().contains('mod');
    final colors = isGame
      ? const [Color(0xFF54218C), Color(0xFF151C4B)]
      : isMod ? const [Color(0xFF153C6B), Color(0xFF33215C)]
      : const [Color(0xFF164778), Color(0xFF41225C)];
    return Container(
      height: 172, width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      child: Stack(fit: StackFit.expand, children: [
        // Fill the banner without stretching portrait artwork: a soft backdrop
        // behind a complete, uncropped foreground image.
        if (localFile != null) ...[
          Image.file(localFile!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          Container(color: const Color(0x99070B1B)),
          Image.file(localFile!, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ] else if (webCovers.isNotEmpty) ...[
          Image.network(webCovers[webIndex], fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          Container(color: const Color(0x99070B1B)),
          Image.network(webCovers[webIndex], fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              final failed = webCovers[webIndex];
              if (failedImages.add(failed)) {
                Future.microtask(() {
                  if (!mounted || webCovers.isEmpty) return;
                  final next = List.generate(webCovers.length, (i) => (webIndex + i + 1) % webCovers.length)
                    .where((i) => !failedImages.contains(webCovers[i]));
                  if (next.isNotEmpty) setState(() => webIndex = next.first);
                });
              }
              return const SizedBox.shrink();
            }),
        ],

        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x22000000), Color(0xCC080D20)]))),
        Positioned(left: 18, right: 18, bottom: 16, child: Text(widget.title.toUpperCase(),
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900,
            shadows: [Shadow(blurRadius: 8, color: Colors.black)]))),
      ]),
    );
  }
}
