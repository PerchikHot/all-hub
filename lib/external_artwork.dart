import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional, device-local artwork for a public GitHub repository.
/// No artwork or file paths are sent to GitHub or included in catalog backups.
class ExternalArtwork {
  static const maxBytes = 10 * 1024 * 1024;
  static const _prefix = 'external_artwork_';

  static bool validImageHeader(List<int> bytes, String extension) {
    final ext = extension.toLowerCase();
    if (ext == 'png') {
      return bytes.length >= 8 &&
          _startsWith(bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    }
    if (ext == 'jpg' || ext == 'jpeg') {
      return _startsWith(bytes, [255, 216, 255]);
    }
    if (ext == 'gif') {
      return _startsWith(bytes, [71, 73, 70, 56, 55, 97]) ||
          _startsWith(bytes, [71, 73, 70, 56, 57, 97]);
    }
    if (ext == 'webp') {
      return bytes.length >= 12 &&
          _startsWith(bytes, [82, 73, 70, 70]) &&
          bytes[8] == 87 && bytes[9] == 69 &&
          bytes[10] == 66 && bytes[11] == 80;
    }
    return false;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _validId(String id) =>
      RegExp(r'^external-[a-z0-9_.-]{3,160}$').hasMatch(id);

  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}external_artwork');
  }

  static Future<String?> load(String projectId) async {
    if (!_validId(projectId)) return null;
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('$_prefix$projectId');
    if (path == null) return null;
    final directory = await _directory();
    // Never follow arbitrary paths from a corrupt preferences file.
    if (!path.startsWith('${directory.path}${Platform.pathSeparator}')) {
      return null;
    }
    return await File(path).exists() ? path : null;
  }

  /// Import a chosen image into private app storage so temporary picker paths
  /// and Android document permissions are not needed for future launches.
  static Future<bool> choose(String projectId) async {
    if (!_validId(projectId)) throw ArgumentError('Invalid project ID');
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.image, allowMultiple: false, withData: false);
    if (selection == null || selection.files.isEmpty) return false;
    final chosen = selection.files.single;
    final path = chosen.path;
    if (path == null) throw const FormatException('Файл недоступен');
    final ext = (chosen.extension ?? '').toLowerCase();
    final source = File(path);
    final size = await source.length();
    if (size < 12 || size > maxBytes) {
      throw const FormatException('Изображение должно быть меньше 10 МБ');
    }
    final header = await source.openRead(0, 16).fold<List<int>>(
        <int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (!validImageHeader(header, ext)) {
      throw const FormatException('Неверный формат PNG, JPG, GIF или WebP');
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    final target = File('${directory.path}${Platform.pathSeparator}$projectId-${DateTime.now().microsecondsSinceEpoch}.$ext');
    await source.copy(target.path);
    final prefs = await SharedPreferences.getInstance();
    final previous = await load(projectId);
    if (!await prefs.setString('$_prefix$projectId', target.path)) {
      await target.delete();
      throw StateError('Не удалось сохранить обложку');
    }
    if (previous != null && previous != target.path) {
      try { await File(previous).delete(); } on FileSystemException { /* optional cleanup */ }
    }
    return true;
  }

  static Future<void> remove(String projectId) async {
    if (!_validId(projectId)) return;
    final previous = await load(projectId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$projectId');
    if (previous != null) {
      try { await File(previous).delete(); } on FileSystemException { /* optional cleanup */ }
    }
  }
}
