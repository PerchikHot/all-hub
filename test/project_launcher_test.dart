import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_launcher.dart';

void main() {
  test('Android APK resumes only from a matching bounded HTTP range', () {
    expect(ProjectLauncher.isSafeApkContentRange('bytes 1024-2047/4096', 1024), isTrue);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 0-1023/1024', 0), isTrue);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 1025-2047/4096', 1024), isFalse);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 1024-4096/4096', 1024), isFalse);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 1024-1000/4096', 1024), isFalse);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 1024-2047/*', 1024), isFalse);
    expect(ProjectLauncher.isSafeApkContentRange(null, 1024), isFalse);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 0-1023/4096', -1), isFalse);
    expect(ProjectLauncher.isSafeApkContentRange('bytes 0-1023/4096', 0, maxBytes: 1024), isFalse);
  });

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

  test('Windows ZIP rejects duplicate and file/directory collisions', () {
    expect(ProjectLauncher.isSafeWindowsArchiveLayout(
      ['bin/app.exe', 'assets/icon.png'], ['bin/', 'assets/']), isTrue);
    expect(ProjectLauncher.isSafeWindowsArchiveLayout(
      ['bin/App.exe', 'BIN/app.EXE'], []), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveLayout(
      ['data', 'data/file.dll'], []), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveLayout(
      ['assets'], ['ASSETS/']), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveLayout(
      ['bin/app.exe'], ['bin/', 'BIN/']), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveLayout(
      ['../outside.exe'], []), isFalse);
  });

  test('Windows ZIP extraction rejects excessive unpacked data', () {
    const mb = 1024 * 1024;
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(10000, 512 * mb, 512 * mb), isTrue);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(10001, 0, 1), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 0, 513 * mb), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 1024 * mb, 1), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 0, -1), isFalse);
  });

  test('Windows ZIP streaming budget stops oversized downloads early', () {
    const mb = 1024 * 1024;
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(0, 256 * mb), isTrue);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(255 * mb, 1 * mb), isTrue);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(255 * mb, 2 * mb), isFalse);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(257 * mb, 0), isFalse);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(-1, 1), isFalse);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(0, -1), isFalse);
  });

  test('standalone Windows EXE uses the same bounded streaming budget', () {
    const mb = 1024 * 1024;
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(0, 256 * mb), isTrue);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(250 * mb, 6 * mb), isTrue);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(250 * mb, 7 * mb), isFalse);
    expect(ProjectLauncher.isSafeWindowsDownloadBudget(0, 33 * mb, maxBytes: 32 * mb), isFalse);
  });

  test('Windows ZIP extraction rejects traversal and reserved device names', () {
    for (final path in [
      '', '/', '../outside.exe', 'assets/../../evil.dll', 'a//b.exe',
      'C:/Windows/evil.exe', 'C:\\Windows\\evil.exe',
      'CON', 'NUL.txt', 'folder/COM1.dll', 'folder/LPT9',
      'folder/./file.exe', 'file.', 'folder /file.exe',
      'images/<preview>.png', 'assets/icon?.png', 'data/file*.dll',
      'data/pipe|name.txt', 'data/quote"name.txt',
    ]) {
      expect(ProjectLauncher.isSafeWindowsArchivePath(path), isFalse,
          reason: path);
    }
  });

}
