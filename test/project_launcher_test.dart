import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_launcher.dart';

void main() {
  test('Windows installation IDs allow known project slugs', () {
    for (final id in ['all-hub', 'kopilka', 'eclipse-arena', 'shadow-rp']) {
      expect(ProjectLauncher.isValidProjectId(id), isTrue, reason: id);
    }
  });

  test('Windows installation IDs cannot contain path traversal or separators', () {
    for (final id in [
      '', '.', '..', '../outside', 'kopilka/../other', 'all-hub/../../',
      'kopilka\\\\other', 'project..', '-project', 'project-', 'a--b',
      'project name', 'C:temp', '/tmp',
    ]) {
      expect(ProjectLauncher.isValidProjectId(id), isFalse, reason: id);
    }
  });
  test('Windows ZIP extraction accepts ordinary portable app paths', () {
    for (final path in [
      'Kopilka.exe', 'bin/runtime.dll', 'assets\\icon.png',
      'data/', 'resources/images/logo.webp',
    ]) {
      expect(ProjectLauncher.isSafeWindowsArchivePath(path), isTrue,
          reason: path);
    }
  });

  test('Windows ZIP extraction rejects traversal and reserved device names', () {
    for (final path in [
      '', '/', '../outside.exe', 'assets/../../evil.dll', 'a//b.exe',
      'C:/Windows/evil.exe', 'C:\\Windows\\evil.exe',
      'CON', 'NUL.txt', 'folder/COM1.dll', 'folder/LPT9',
      'folder/./file.exe', 'file.', 'folder /file.exe',
    ]) {
      expect(ProjectLauncher.isSafeWindowsArchivePath(path), isFalse,
          reason: path);
    }
  });

}
