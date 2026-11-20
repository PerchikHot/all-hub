import 'dart:io';
import 'dart:typed_data';

/// Private on-device storage for images generated in the Eyra chat.
/// The caller supplies an application-owned directory, never a user path.
class EyraChatImageStore {
  EyraChatImageStore(this.directory);
  final Directory directory;
  int _sequence = 0;

  // Validate the complete container, not just its first few magic bytes.
  // This is a structural check, not a guarantee that every decoder accepts
  // the image. Keep the 24 MiB bound before walking attacker-supplied chunks.
  static int _u32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  static bool _validPng(Uint8List b) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (b.length < 45) return false;
    for (var i = 0; i < signature.length; i++) {
      if (b[i] != signature[i]) return false;
    }
    var offset = 8;
    var seenHeader = false;
    var seenData = false;
    while (offset + 12 <= b.length) {
      final length = _u32(b, offset);
      if (length > b.length - offset - 12) return false;
      final type = String.fromCharCodes(b.sublist(offset + 4, offset + 8));
      if (!seenHeader) {
        if (type != 'IHDR' || length != 13) return false;
        final width = _u32(b, offset + 8);
        final height = _u32(b, offset + 12);
        if (width == 0 || height == 0 || width > 32768 || height > 32768) {
          return false;
        }
        seenHeader = true;
      } else if (type == 'IHDR') {
        return false;
      }
      if (type == 'IDAT') seenData = true;
      if (type == 'IEND') {
        return length == 0 && seenData && offset + 12 == b.length;
      }
      offset += 12 + length;
    }
    return false;
  }

  static bool _validJpeg(Uint8List b) {
    if (b.length < 12 || b[0] != 0xff || b[1] != 0xd8 ||
        b[b.length - 2] != 0xff || b.last != 0xd9) return false;
    // Require a real marker segment after SOI; reject header-only fakes.
    if (b[2] != 0xff || b[3] == 0x00 || b[3] == 0xd9) return false;
    return true;
  }

  Future<String> save(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 24 * 1024 * 1024) {
      throw const FormatException('Некорректный размер изображения Forge');
    }
    final png = _validPng(bytes);
    final jpeg = !png && _validJpeg(bytes);
    if (!png && !jpeg) {
      throw const FormatException('Forge вернул повреждённый PNG/JPEG');
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
    return RegExp(r'^\d+_\d+\.(png|jpg)$').hasMatch(name);
  }

  Future<void> delete(String path) async {
    if (!owns(path)) return;
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
