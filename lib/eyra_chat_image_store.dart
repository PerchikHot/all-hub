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

  /// Only application-owned image paths are eligible for deletion.
  /// URI normalization uses forward slashes on both Windows and Android;
  /// Platform.pathSeparator alone is unreliable for mixed Windows paths.
  bool owns(String path) {
    if (path.isEmpty) return false;
    final root = directory.absolute.uri.normalizePath();
    final candidate = File(path).absolute.uri.normalizePath();
    final rootPath = root.path.endsWith('/') ? root.path : '${root.path}/';
    final imagePath = candidate.path;
    final sameVolume = root.scheme == candidate.scheme &&
        root.authority.toLowerCase() == candidate.authority.toLowerCase();
    if (!sameVolume) return false;
    final left = Platform.isWindows ? rootPath.toLowerCase() : rootPath;
    final right = Platform.isWindows ? imagePath.toLowerCase() : imagePath;
    // No subdirectories are created by this store; disallow nested paths.
    if (!right.startsWith(left)) return false;
    final name = right.substring(left.length);
    return RegExp(r'^\d+_\d+\.(png|jpg)).hasMatch(name);
  }

  Future<void> delete(String path) async {
    if (!owns(path)) return;
    // Never follow links or remove user-controlled targets.
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
).hasMatch(name);
  }

  Future<void> delete(String path) async {
    if (!owns(path)) return;
    // Never follow links or remove user-controlled targets.
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
