import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:all_hub/project_launcher.dart';
import 'package:all_hub/external_repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('update manager serializes installs and releases lock on failure', () async {
    final gate = Completer<void>();
    final first = ProjectLauncher.runInstallExclusive('shadow-rp', () async {
      await gate.future;
      return 42;
    });
    await expectLater(
      ProjectLauncher.runInstallExclusive('kopilka', () async => 0),
      throwsStateError,
    );
    gate.complete();
    expect(await first, 42);
    await expectLater(
      ProjectLauncher.runInstallExclusive('kopilka', () async {
        throw StateError('failed update');
      }),
      throwsStateError,
    );
    expect(await ProjectLauncher.runInstallExclusive('kopilka', () async => 7), 7);
    await expectLater(
      ProjectLauncher.runInstallExclusive('../outside', () async => 0),
      throwsArgumentError,
    );
  });

  test('resumable APK restarts after stale GitHub HTTP 416 range', () async {
    final directory = await Directory.systemTemp.createTemp('allhub-range-');
    final file = File('${directory.path}/partial.apk.download');
    final ranges = <String?>[];
    final client = MockClient((request) async {
      ranges.add(request.headers['Range']);
      if (ranges.length == 1) {
        return http.Response('', 416);
      }
      return http.Response('new-apk-bytes', 200);
    });
    try {
      await file.writeAsBytes([1, 2, 3, 4]);
      await ProjectLauncher.downloadResumableApk(
          client, Uri.parse('https://github.com/example/release.apk'), file);
      expect(ranges, ['bytes=4-', null]);
      expect(await file.readAsString(), 'new-apk-bytes');
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test('Windows version receipt requires an existing registered EXE', () async {
    final directory = await Directory.systemTemp.createTemp('allhub-receipt-');
    try {
      final executable = File('${directory.path}/shadow-rp.exe');
      SharedPreferences.setMockInitialValues({
        'exe_shadow-rp': executable.path,
        'installed_version_shadow-rp': '0.18.6',
      });
      expect(await ProjectLauncher.installedWindowsVersion('shadow-rp'), isNull);
      await executable.writeAsBytes([0x4d, 0x5a, 0, 0]);
      expect(await ProjectLauncher.installedWindowsVersion('shadow-rp'), '0.18.6');
      await executable.delete();
      expect(await ProjectLauncher.installedWindowsVersion('shadow-rp'), isNull);
      expect(await ProjectLauncher.installedWindowsVersion('../outside'), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Windows updater restores interrupted installs without overwriting new ones', () async {
    final root = await Directory.systemTemp.createTemp('allhub-recovery-');
    try {
      final exe = File('${root.path}/shadow-rp.exe');
      final exeBackup = File('${exe.path}.backup');
      await exeBackup.writeAsBytes([0x4d, 0x5a, 1]);
      expect(await ProjectLauncher.recoverInterruptedWindowsExe(exe), isTrue);
      expect(await exe.readAsBytes(), [0x4d, 0x5a, 1]);
      expect(await ProjectLauncher.recoverInterruptedWindowsExe(exe), isFalse);
      await exeBackup.writeAsBytes([0x4d, 0x5a, 2]);
      expect(await ProjectLauncher.recoverInterruptedWindowsExe(exe), isFalse);
      expect(await exe.readAsBytes(), [0x4d, 0x5a, 1]);

      final app = Directory('${root.path}/nova-game');
      final backup = Directory('${app.path}.backup');
      await backup.create();
      await File('${backup.path}/NovaGame.exe').writeAsBytes([0x4d, 0x5a]);
      expect(await ProjectLauncher.recoverInterruptedWindowsZip(app), isTrue);
      expect(await File('${app.path}/NovaGame.exe').exists(), isTrue);
      expect(await ProjectLauncher.recoverInterruptedWindowsZip(app), isFalse);
      await backup.create();
      await File('${backup.path}/old.exe').writeAsBytes([0x4d, 0x5a]);
      expect(await ProjectLauncher.recoverInterruptedWindowsZip(app), isFalse);
      expect(await File('${app.path}/old.exe').exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('published SHA-256 digest rejects modified download before install', () async {
    final dir = await Directory.systemTemp.createTemp('allhub-digest-');
    try {
      final file = File('${dir.path}/test.bin');
      await file.writeAsString('abc');
      const expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      await ProjectLauncher.verifyDownloadedDigest(file, expected);
      await file.writeAsString('abd');
      await expectLater(ProjectLauncher.verifyDownloadedDigest(file, expected),
          throwsFormatException);
      await expectLater(ProjectLauncher.verifyDownloadedDigest(file, 'bad'),
          throwsFormatException);
      await ProjectLauncher.verifyDownloadedDigest(file, null);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('Windows installer rejects truncated HTTP payloads before activation', () {
    ProjectLauncher.requireCompleteWindowsDownload(1024, 1024);
    ProjectLauncher.requireCompleteWindowsDownload(1024, null);
    for (final values in <(int, int?)>[(1023, 1024), (1025, 1024),
                                       (-1, null), (0, -1)]) {
      expect(() => ProjectLauncher.requireCompleteWindowsDownload(
          values.$1, values.$2), throwsFormatException);
    }
  });

  test('Windows update cannot be reported complete without a saved launcher path', () {
    expect(() => ProjectLauncher.requireWindowsInstallRegistered(true),
        returnsNormally);
    expect(() => ProjectLauncher.requireWindowsInstallRegistered(false),
        throwsStateError);
  });

  test('Android installer failures are never reported as completed updates', () {
    expect(() => ProjectLauncher.requireAndroidInstallerOpened(true), returnsNormally);
    expect(() => ProjectLauncher.requireAndroidInstallerOpened(false), throwsStateError);
    expect(() => ProjectLauncher.requireAndroidInstallerOpened(null), throwsStateError);
  });

  test('installer binds official and manually registered APK package names', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ProjectLauncher.expectedAndroidPackageName('all-hub'),
        'com.example.all_hub');
    expect(await ProjectLauncher.expectedAndroidPackageName('shadow-rp'),
        'com.shadowrp.app');
    expect(await ProjectLauncher.expectedAndroidPackageName('kopilka'),
        'com.veyrion.kopilka_app');
    final repo = ExternalRepository.parse('ExampleOrg/Widget-App')!;
    expect(await ProjectLauncher.expectedAndroidPackageName(repo.projectId), isNull);
    await ProjectLauncher.setExternalPackageName(repo.projectId, 'com.example.widget');
    expect(await ProjectLauncher.expectedAndroidPackageName(repo.projectId),
        'com.example.widget');
    expect(await ProjectLauncher.expectedAndroidPackageName('../bad'), isNull);
  });

  test('manual Android package binding validates IDs and stays local', () async {
    SharedPreferences.setMockInitialValues({});
    final id = ExternalRepository.parse('ExampleOrg/Widget-App')!.projectId;
    expect(ProjectLauncher.isValidAndroidPackageName('com.example.widget'), isTrue);
    for (final invalid in [
      '', 'widget', 'com..widget', '.com.widget',
      'com.widget/', 'com.widget;rm', 'com.widget with space',
    ]) {
      expect(ProjectLauncher.isValidAndroidPackageName(invalid), isFalse,
          reason: invalid);
    }
    expect(await ProjectLauncher.setExternalPackageName(
        id, 'com.example.widget'), isTrue);
    expect(await ProjectLauncher.externalPackageName(id), 'com.example.widget');
    await expectLater(
        ProjectLauncher.setExternalPackageName('all-hub', 'com.example.widget'),
        throwsArgumentError);
  });

  test('external installer accepts only a matching public release URL', () {
    final repo = ExternalRepository.parse('ExampleOrg/Widget-App')!;
    const good = 'https://github.com/ExampleOrg/Widget-App/releases/download/v1.2.3/Widget-Android.apk';
    expect(ProjectLauncher.isTrustedExternalDownload(
        repo.projectId, repo.fullName, good, 'apk'), isTrue);
    for (final bad in [
      'https://github.com/other/Widget-App/releases/download/v1.2.3/Widget-Android.apk',
      'https://github.com/ExampleOrg/Widget-App/releases/download/v1.2.3/Widget-Android.apk?token=abc',
      'http://github.com/ExampleOrg/Widget-App/releases/download/v1.2.3/Widget-Android.apk',
      'https://evil.example/ExampleOrg/Widget-App/releases/download/v1.2.3/Widget-Android.apk',
      'https://github.com/ExampleOrg/Widget-App/releases/download/v1.2.3/Widget-Windows.exe',
    ]) {
      expect(ProjectLauncher.isTrustedExternalDownload(
          repo.projectId, repo.fullName, bad, 'apk'), isFalse, reason: bad);
    }
    expect(ProjectLauncher.isTrustedExternalDownload(
        'external-wrong-id', repo.fullName, good, 'apk'), isFalse);
  });

  test('installer accepts only the matching project release and platform', () {
    expect(ProjectLauncher.isTrustedProjectDownload(
      'all-hub',
      'https://github.com/PerchikHot/all-hub/releases/download/all-hub-v0.7.0%2B633/AllHub-Android.apk',
      'apk'), isTrue);
    expect(ProjectLauncher.isTrustedProjectDownload(
      'kopilka',
      'https://github.com/PerchikHot/all-hub/releases/download/kopilka-latest/Kopilka-Android.apk',
      'apk'), isTrue);
    expect(ProjectLauncher.isTrustedProjectDownload(
      'shadow-rp',
      'https://github.com/PerchikHot/Shadow-rp/releases/download/shadow-rp-android/ShadowRP-Android.apk',
      'apk'), isTrue);
    expect(ProjectLauncher.isTrustedProjectDownload(
      'eclipse-arena',
      'https://github.com/PerchikHot/Eclipse-Arena-/releases/download/eclipse-arena-windows/EclipseArena.exe',
      'exe'), isTrue);
    for (final url in [
      'https://github.com:443/PerchikHot/all-hub/releases/download/all-hub-v1/App-Android.apk',
      'https://github.com:8443/PerchikHot/all-hub/releases/download/all-hub-v1/App-Android.apk',
      'https://user@github.com/PerchikHot/all-hub/releases/download/all-hub-v1/App-Android.apk',
      'https://github.com/PerchikHot/all-hub/releases/download/kopilka-latest/Kopilka-Android.apk',
      'https://github.com/attacker/all-hub/releases/download/all-hub-v1.0.0/payload.apk',
      'https://github.com/PerchikHot/all-hub/releases/download/all-hub-latest/payload.apk?x=1',
      'https://github.com/PerchikHot/all-hub/releases/download/all-hub-latest/payload.exe',
    ]) {
      expect(ProjectLauncher.isTrustedProjectDownload('all-hub', url, 'apk'),
          isFalse, reason: url);
    }
  });

  test('resumable APKs are isolated by project and release', () {
    const first = 'https://github.com/PerchikHot/all-hub/releases/download/all-hub-v0.7.0%2B645/AllHub-Android.apk';
    const second = 'https://github.com/PerchikHot/all-hub/releases/download/all-hub-v0.7.0%2B651/AllHub-Android.apk';
    const kopilka = 'https://github.com/PerchikHot/all-hub/releases/download/kopilka-latest/Kopilka-Android.apk';
    final key = ProjectLauncher.androidApkCacheName('all-hub', first);
    expect(key, endsWith('.apk'));
    expect(key.contains('/'), isFalse);
    expect(key.contains('\\\\'), isFalse);
    expect(key, isNot(ProjectLauncher.androidApkCacheName('all-hub', second)));
    expect(key, isNot(ProjectLauncher.androidApkCacheName('kopilka', kopilka)));
    expect(() => ProjectLauncher.androidApkCacheName('all-hub', kopilka), throwsArgumentError);
  });

  test('Windows ZIP chooses the actual application without a file picker', () {
    expect(ProjectLauncher.selectWindowsLaunchExecutable('shadow-rp', [
      r'bin\\python.exe', r'ShadowRP.exe', r'bin\\helper.exe',
    ]), r'ShadowRP.exe');
    expect(ProjectLauncher.selectWindowsLaunchExecutable('eclipse-arena', [
      'uninstall.exe', 'EclipseArena.exe',
    ]), 'EclipseArena.exe');
    expect(ProjectLauncher.selectWindowsLaunchExecutable('kopilka', [
      'Kopilka.exe', 'KopilkaUpdater.exe',
    ]), 'Kopilka.exe');
    expect(ProjectLauncher.selectWindowsLaunchExecutable('nova-game', [
      'NovaGame.exe',
    ]), 'NovaGame.exe');
    expect(ProjectLauncher.selectWindowsLaunchExecutable('external-example', [
      'helper.exe', 'another.exe',
    ]), isNull);
    expect(ProjectLauncher.selectWindowsLaunchExecutable('shadow-rp', [
      'uninstall.exe', 'setup.exe',
    ]), isNull);
    expect(ProjectLauncher.selectWindowsLaunchExecutable('kopilka', [
      'KopilkaUpdater.exe', 'KopilkaInstaller.exe',
    ]), isNull);
    expect(ProjectLauncher.selectWindowsLaunchExecutable('../bad', [
      'good.exe',
    ]), isNull);
  });

  test('Windows installer rejects fake MZ, corrupt PE and truncated files', () {
    List<int> pe({int offset = 0x80, int machine = 0x8664,
        int magic = 0x20b, int sections = 3}) {
      final bytes = List<int>.filled(1024, 0);
      bytes[0] = 0x4d;
      bytes[1] = 0x5a;
      bytes[0x3c] = offset & 0xff;
      bytes[0x3d] = (offset >> 8) & 0xff;
      bytes[offset] = 0x50;
      bytes[offset + 1] = 0x45;
      bytes[offset + 4] = machine & 0xff;
      bytes[offset + 5] = (machine >> 8) & 0xff;
      bytes[offset + 6] = sections;
      bytes[offset + 20] = 0xf0; // Optional header length.
      bytes[offset + 24] = magic & 0xff;
      bytes[offset + 25] = magic >> 8;
      return bytes;
    }
    expect(ProjectLauncher.hasWindowsExecutableHeader(pe()), isTrue);
    expect(ProjectLauncher.hasWindowsExecutableHeader(
        pe(machine: 0x14c, magic: 0x10b)), isTrue);
    expect(ProjectLauncher.hasWindowsExecutableHeader(
        pe(machine: 0xaa64)), isTrue);
    expect(ProjectLauncher.hasWindowsExecutableHeader([0x4d, 0x5a, 0, 0]), isFalse);
    expect(ProjectLauncher.hasWindowsExecutableHeader([0x50, 0x4b]), isFalse);
    expect(ProjectLauncher.hasWindowsExecutableHeader([]), isFalse);
    final fake = pe()..[0x80] = 0;
    expect(ProjectLauncher.hasWindowsExecutableHeader(fake), isFalse);
    expect(ProjectLauncher.hasWindowsExecutableHeader(pe(machine: 0)), isFalse);
    expect(ProjectLauncher.hasWindowsExecutableHeader(pe(sections: 0)), isFalse);
    expect(ProjectLauncher.hasWindowsExecutableHeader(pe().sublist(0, 200)), isFalse);
    final offsetOutside = pe()..[0x3d] = 0x7f;
    expect(ProjectLauncher.hasWindowsExecutableHeader(offsetOutside), isFalse);
  });

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
    // Untrusted ZIP metadata must not wrap the cumulative size limit.
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 1024 * mb, 0), isTrue);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 1024 * mb + 1, 0), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 9223372036854775807, 1), isFalse);
    expect(ProjectLauncher.isSafeWindowsArchiveBudget(1, 1024 * mb - 1, 2), isFalse);
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
