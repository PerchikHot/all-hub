import 'dart:io';
import 'package:crypto/crypto.dart';

class EyraFileInspection {
  final int bytes;
  final String sha256;
  const EyraFileInspection(this.bytes, this.sha256);
}

/// Reads only the explicitly selected file; no directory traversal, upload,
/// modification or persistence. Streaming prevents loading entire files into RAM.
class EyraFileInspector {
  static const maxBytes = 256 * 1024 * 1024;

  static Future<EyraFileInspection> inspect(File file) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FormatException('Выбран не обычный файл');
    }
    if (stat.size < 0 || stat.size > maxBytes) {
      throw const FormatException('Файл превышает лимит 256 МиБ');
    }
    var count = 0;
    final bounded = file.openRead().map((chunk) {
      count += chunk.length;
      if (count > maxBytes) {
        throw const FormatException('Файл превысил лимит при чтении');
      }
      return chunk;
    });
    final digest = await sha256.bind(bounded).first;
    if (count != stat.size) {
      throw const FormatException('Размер файла изменился во время проверки');
    }
    return EyraFileInspection(count, digest.toString());
  }
}
