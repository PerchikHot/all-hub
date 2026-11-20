import 'dart:io';
import 'package:crypto/crypto.dart';

/// Only a display name: never allow a picker-provided path to escape models/.
String safeGgufFilename(String filename) {
  final basename = filename.replaceAll('\\', '/').split('/').last;
  final sanitized = basename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  if (sanitized.isEmpty || sanitized.startsWith('.') ||
      !sanitized.toLowerCase().endsWith('.gguf')) {
    throw const FormatException('Недопустимое имя GGUF');
  }
  return sanitized.length <= 120
      ? sanitized : '${sanitized.substring(0, 115)}.gguf';
}

/// Comparing lengths alone misses same-size corruption in a copied model.
Future<bool> ggufCopiesMatch(File source, File destination) async {
  if (!await source.exists() || !await destination.exists()) return false;
  if (await source.length() != await destination.length()) return false;
  final original = await sha256.bind(source.openRead()).first;
  final copied = await sha256.bind(destination.openRead()).first;
  return original == copied;
}
