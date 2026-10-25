import 'dart:async';
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
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    folder = prefs.getString('desktop_cover_folder');
    revision.value++;
  }
  static Future<bool> chooseFolder() async {
    if (!Platform.isWindows && !Platform.isAndroid) return false;
    String? selected;
    try {
      selected = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Папка с обложками All Hub');
    } catch (_) {
      return false;
    }
    if (selected == null) {
      if (!Platform.isAndroid) return false;
      // Android's document provider may not expose a readable directory path.
      // Import selected photos into persistent app storage instead.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: true, withData: false);
      if (picked == null || picked.files.isEmpty) return false;
      final base = await getApplicationSupportDirectory();
      final imported = Directory('${base.path}/all_hub_covers');
      await imported.create(recursive: true);
      var count = 0;
      for (final item in picked.files) {
        if (item.path == null) continue;
        try {
          final ext = item.extension?.toLowerCase() ?? 'jpg';
          if (!['png', 'jpg', 'jpeg', 'webp', 'bmp'].contains(ext)) continue;
          await File(item.path!).copy('${imported.path}/cover_${DateTime.now().microsecondsSinceEpoch}_$count.$ext');
          count++;
        } catch (_) {}
      }
      if (count == 0) return false;
      selected = imported.path;
    }
    folder = selected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('desktop_cover_folder', selected);
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
  int generation = 0;
  Timer? rotationTimer;
  @override
  void initState() {
    super.initState();
    CoverSettings.revision.addListener(refresh);
    refresh();
    rotationTimer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }
  @override
  void didUpdateWidget(covariant ProjectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) refresh();
  }
  @override
  void dispose() {
    rotationTimer?.cancel();
    CoverSettings.revision.removeListener(refresh);
    super.dispose();
  }
  Future<void> refresh() async {
    final current = ++generation;
    File? selected;
    final folder = CoverSettings.folder;
    if ((Platform.isWindows || Platform.isAndroid) && folder != null) {
      try {
        final dir = Directory(folder);
        if (await dir.exists()) {
          final files = await dir.list(followLinks: false).where((entry) =>
            entry is File && RegExp(r'\.(png|jpg|jpeg|webp|bmp)$', caseSensitive: false).hasMatch(entry.path)
          ).cast<File>().toList();
          if (files.isNotEmpty) {
            final alternatives = files.where((f) => f.path != localFile?.path).toList();
            final candidates = alternatives.isNotEmpty ? alternatives : files;
            selected = candidates[Random().nextInt(candidates.length)];
          }
        }
      } catch (_) { /* Inaccessible directory: show built-in fallback. */ }
    }
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
        if (localFile != null)
          Image.file(localFile!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const SizedBox.shrink()),

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
