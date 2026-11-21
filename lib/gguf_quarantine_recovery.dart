import 'dart:io';

/// Recovers an interrupted GGUF removal without deleting user data.
///
/// The saved model list is the source of truth. If the model is still
/// registered, restore its quarantined file. If it is no longer registered,
/// leave the quarantine untouched for manual recovery; never guess that
/// an unreferenced multi-gigabyte file can be destroyed.
Future<int> recoverQuarantinedGguf(
    Directory managedDirectory, List<String> registeredPaths) async {
  if (!await managedDirectory.exists()) return 0;
  final registered = registeredPaths.map((p) => File(p).absolute.path).toSet();
  var restored = 0;
  await for (final entity in managedDirectory.list(followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.absolute.path;
    final marker = RegExp(r'\.deleting-[0-9]+$').firstMatch(path);
    if (marker == null) continue;
    final originalPath = path.substring(0, marker.start);
    if (!originalPath.toLowerCase().endsWith('.gguf')) continue;
    if (!registered.contains(originalPath)) continue;
    if (await File(originalPath).exists()) continue;
    await entity.rename(originalPath);
    restored++;
  }
  return restored;
}
