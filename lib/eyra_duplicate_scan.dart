import 'dart:io';
import 'eyra_file_inspector.dart';

/// Foreground-only duplicate analysis of files explicitly chosen by the user.
/// No directory traversal, deletion, uploads or persistent file paths.
class EyraDuplicateGroup {
  final int bytes;
  final String sha256;
  final List<String> names;
  const EyraDuplicateGroup(this.bytes, this.sha256, this.names);
}

class EyraDuplicateScan {
  static const maxFiles = 30;

  static Future<List<EyraDuplicateGroup>> scan(
    List<File> files, {
    Future<bool> Function()? stillAllowed,
  }) async {
    if (files.length < 2 || files.length > maxFiles) {
      throw const FormatException('Выберите от 2 до 30 файлов');
    }
    final paths = files.map((file) => file.absolute.path).toList();
    if (paths.toSet().length != paths.length) {
      throw const FormatException('Один файл выбран несколько раз');
    }
    final groups = <String, List<String>>{};
    final sizes = <String, int>{};
    for (final file in files) {
      if (stillAllowed != null && !await stillAllowed()) {
        throw const FormatException('Разрешение на проверку отозвано');
      }
      final info = await EyraFileInspector.inspect(file);
      final key = '${info.bytes}:${info.sha256}';
      groups.putIfAbsent(key, () => <String>[]).add(file.uri.pathSegments.last);
      sizes[key] = info.bytes;
    }
    if (stillAllowed != null && !await stillAllowed()) {
      throw const FormatException('Разрешение на проверку отозвано');
    }
    return [
      for (final entry in groups.entries)
        if (entry.value.length > 1)
          EyraDuplicateGroup(
            sizes[entry.key]!, entry.key.split(':').last,
            List.unmodifiable(entry.value),
          ),
    ];
  }
}
