import 'dart:io';
import 'dart:typed_data';

/// Private on-device storage for images generated in the Eyra chat.
/// The caller supplies an application-owned directory, never a user path.
class EyraChatImageStore {
  EyraChatImageStore(this.directory);
  final Directory directory;
  int _sequence = 0;

  Future<String> save(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 24 * 1024 * 1024) {
      throw const FormatException('Некорректный размер изображения Forge');
    }
    final png = bytes.length >= 8 &&
        bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71;
    final jpeg = bytes.length >= 3 &&
        bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    if (!png && !jpeg) {
      throw const FormatException('Forge вернул не PNG/JPEG');
    }
    await directory.create(recursive: true);
    final name = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}.${png ? 'png' : 'jpg'}';
    final temp = File('${directory.path}/$name.part');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      return (await temp.rename('${directory.path}/$name')).path;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Reject paths outside our private directory, including ../ traversal.
  bool owns(String path) {
    final root = directory.absolute.path;
    final candidate = File(path).absolute.path;
    final normalized = _normalize(candidate);
    return normalized.startsWith('${_normalize(root)}${Platform.pathSeparator}');
  }

  String _normalize(String path) {
    final parts = <String>[];
    for (final part in path.split(Platform.pathSeparator)) {
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (part.isNotEmpty && part != '.') {
        parts.add(part);
      }
    }
    return '${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}';
  }

  Future<void> delete(String path) async {
    if (!owns(path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
