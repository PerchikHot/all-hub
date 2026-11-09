import 'dart:io';
import 'package:crypto/crypto.dart';
import 'external_repositories.dart';
import 'hub_service.dart';
import 'version_status.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ProjectLauncher {
  /// Only verified project-specific GitHub release assets may be installed.
  /// This also prevents accidentally installing another Veyrion app's APK.
  static bool isTrustedProjectDownload(String id, String url, String extension) {
    const repos = <String, String>{
      'all-hub': 'all-hub',
      'kopilka': 'all-hub',
      'nova-game': '-',
      'shadow-rp': 'Shadow-rp',
      'eclipse-arena': 'Eclipse-Arena-',
    };
    final repo = repos[id];
    // Match the same strict origin rule as third-party GitHub assets.
    // Never trust a normalized :443 authority or embedded credentials.
    if (!RegExp(r'^https://github\.com/', caseSensitive: false).hasMatch(url)) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (repo == null || !['apk', 'exe', 'zip'].contains(extension) ||
        uri == null || uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.authority.toLowerCase() != 'github.com' || uri.hasPort ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    return parts.length == 6 &&
        parts[4].length <= 100 && parts[5].length <= 120 &&
        parts[0].toLowerCase() == 'perchikhot' &&
        parts[1].toLowerCase() == repo.toLowerCase() &&
        parts[2] == 'releases' && parts[3] == 'download' &&
        releaseMatchesProject(parts[4], id) &&
        parts[5].isNotEmpty &&
        !parts[5].contains('/') && !parts[5].contains('\\\\') &&
        parts[5].toLowerCase().endsWith('.$extension');
  }

  /// Third-party apps are opt-in. A saved repository authorizes ONLY its own
  /// published GitHub release URLs, not arbitrary redirects or other hosts.
  static bool isTrustedExternalDownload(
      String id, String repo, String url, String extension) {
    final external = ExternalRepository.parse(repo);
    final uri = Uri.tryParse(url);
    if (external == null || external.projectId != id ||
        !['apk', 'exe', 'zip'].contains(extension) || uri == null ||
        uri.pathSegments.length != 6) {
      return false;
    }
    final parts = uri.pathSegments;
    final filename = parts.last;
    if (parts[4].isEmpty || parts[4].length > 100 ||
        filename.length > 200 ||
        !filename.toLowerCase().endsWith('.$extension') ||
        HubService.assetPlatform(filename) !=
            (extension == 'apk' ? 'android' : 'windows')) {
      return false;
    }
    return HubService.isTrustedReleaseAssetUrl(external.fullName, url,
        expectedName: filename, expectedTag: parts[4]);
  }

  /// Isolate resumable APK files by project, release and asset. Otherwise an
  /// interrupted download from one release could be resumed as another APK.
  static String androidApkCacheName(String id, String url) {
    if (!isTrustedProjectDownload(id, url, 'apk')) {
      throw ArgumentError('Недопустимый APK релиз');
    }
    final parts = Uri.parse(url).pathSegments;
    return ('${id}_${parts[4]}_${parts[5]}')
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  /// Validate the actual Portable Executable signature, not just "MZ".
  /// An HTML/error response or a truncated DOS stub must never replace a
  /// previously working Windows installation. Only read the first 8 KiB.
  static bool hasWindowsExecutableHeader(List<int> bytes) {
    if (bytes.length < 0x40 || bytes[0] != 0x4d || bytes[1] != 0x5a) {
      return false;
    }
    int u16(int offset) => bytes[offset] | (bytes[offset + 1] << 8);
    final peOffset = bytes[0x3c] | (bytes[0x3d] << 8) |
        (bytes[0x3e] << 16) | (bytes[0x3f] << 24);
    // e_lfanew must point beyond the DOS header, within the bounded prefix.
    if (peOffset < 0x40 || peOffset > bytes.length - 26) return false;
    if (bytes[peOffset] != 0x50 || bytes[peOffset + 1] != 0x45 ||
        bytes[peOffset + 2] != 0 || bytes[peOffset + 3] != 0) {
      return false;
    }
    final machine = u16(peOffset + 4);
    final sections = u16(peOffset + 6);
    final optionalSize = u16(peOffset + 20);
    if (!const {0x14c, 0x8664, 0xaa64}.contains(machine) ||
        sections == 0 || sections > 96 || optionalSize < 2 ||
        peOffset + 24 + optionalSize > bytes.length) {
      return false;
    }
    final magic = u16(peOffset + 24);
    return magic == 0x10b || magic == 0x20b;
  }

  // Project IDs become Windows directory names: never accept path segments.
  static bool isValidProjectId(String id) =>
      RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id);
  /// A crash between moving the old install to .backup and activating the
  /// new one can leave no launchable app. Recover it before a new update.
  /// Never overwrite a present target: that might be a successfully updated
  /// version whose backup cleanup was interrupted.
  static Future<bool> recoverInterruptedWindowsExe(File target) async {
    final backup = File('${target.path}.backup');
    if (await target.exists() || !await backup.exists()) return false;
    await backup.rename(target.path);
    return true;
  }

  static Future<bool> recoverInterruptedWindowsZip(Directory target) async {
    final backup = Directory('${target.path}.backup');
    if (await target.exists() || !await backup.exists()) return false;
    await backup.rename(target.path);
    return true;
  }

  /// Pick the portable app's EXE without opening a manual file chooser.
  /// Archives with multiple unrelated executables are ambiguous and must
  /// not silently launch an uninstaller or an arbitrary helper program.
  static String? selectWindowsLaunchExecutable(
      String id, Iterable<String> relativePaths) {
    if (!isValidProjectId(id)) return null;
    final paths = relativePaths.toList(growable: false);
    if (paths.isEmpty) return null;
    final candidates = paths.where((path) {
      final filename = path.replaceAll('\\', '/').split('/').last.toLowerCase();
      return filename.endsWith('.exe') &&
          // Some archives name a maintenance binary "KopilkaUpdater.exe".
          // A sole updater must never become the registered app launcher.
          !RegExp(r'uninstall|updater|installer|setup|crashreport|^unins')
              .hasMatch(filename);
    }).toList(growable: false);
    if (candidates.isEmpty) return null;
    final slug = id.replaceAll('-', '');
    String normalizedName(String path) => path.replaceAll('\\', '/')
        .split('/').last.toLowerCase().replaceAll('.exe', '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final exact = candidates.where((path) => normalizedName(path) == slug)
        .toList(growable: false);
    if (exact.length == 1) return exact.single;
    final matches = candidates.where((path) =>
        normalizedName(path).contains(slug)).toList(growable: false);
    if (matches.length == 1) return matches.single;
    return candidates.length == 1 ? candidates.single : null;
  }

  /// Reject Windows-unsafe archive members before extracting portable apps.
  /// ZIP paths may use either separator, but may not escape the staging root.
  static bool isSafeWindowsArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty || normalized.startsWith('/') ||
        RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(normalized)) {
      return false;
    }
    final parts = normalized.split('/');
    if (parts.last.isEmpty) parts.removeLast(); // directory entry
    if (parts.isEmpty) return false;
    final reserved = RegExp(
      r'^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
      caseSensitive: false,
    );
    return parts.every((part) => part.isNotEmpty && part != '.' &&
        part != '..' && part.trim() == part && !part.endsWith('.') &&
        !reserved.hasMatch(part));
  }

  /// Reject duplicate paths and file/directory collisions on Windows.
  static bool isSafeWindowsArchiveLayout(
    Iterable<String> filePaths, Iterable<String> directoryPaths,
  ) {
    String normalize(String path) => path.replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '').toLowerCase();
    final files = <String>{};
    final directories = <String>{};
    for (final path in filePaths) {
      if (!isSafeWindowsArchivePath(path) || !files.add(normalize(path))) {
        return false;
      }
    }
    for (final path in directoryPaths) {
      if (!isSafeWindowsArchivePath(path) || !directories.add(normalize(path))) {
        return false;
      }
    }
    if (files.any(directories.contains)) return false;
    for (final path in [...files, ...directories]) {
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        if (files.contains(parts.take(i).join('/'))) return false;
      }
    }
    return true;
  }

  /// Cap archive entries and unpacked size to avoid exhausting disk space.
  /// These checks apply before writing each entry to the staging directory.
  static bool isSafeWindowsArchiveBudget(
    int entryCount, int totalBytes, int nextEntryBytes,
  ) => entryCount >= 0 && entryCount <= 10000 &&
      totalBytes >= 0 && nextEntryBytes >= 0 &&
      nextEntryBytes <= 512 * 1024 * 1024 &&
      totalBytes <= 1024 * 1024 * 1024 &&
      // Subtraction avoids overflow on malformed ZIP size metadata.
      nextEntryBytes <= 1024 * 1024 * 1024 - totalBytes;

  /// Reject oversized streaming downloads before consuming more disk space.
  static bool isSafeWindowsDownloadBudget(int received, int nextChunk, {int maxBytes = 256 * 1024 * 1024}) =>
      received >= 0 && nextChunk >= 0 && maxBytes >= 0 &&
      received <= maxBytes && nextChunk <= maxBytes - received;

  /// A resumed APK must start at the exact saved offset and declare a
  /// bounded total size. Never append a mismatched server response.
  static bool isSafeApkContentRange(String? header, int existing,
      {int maxBytes = 256 * 1024 * 1024}) {
    if (header == null || existing < 0 || maxBytes <= 0) return false;
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
        .firstMatch(header.trim());
    if (match == null) return false;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    return start != null && end != null && total != null &&
        start == existing && end >= start && total > end &&
        total <= maxBytes;
  }

  /// Users register a third-party Android package explicitly. Android only
  /// permits launching visible apps; no private app data is accessed.
  static bool isValidAndroidPackageName(String value) =>
      value.length <= 200 &&
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+$')
          .hasMatch(value);

  static Future<bool> setExternalPackageName(String id, String packageName) async {
    if (!id.startsWith('external-') || !isValidProjectId(id) ||
        !isValidAndroidPackageName(packageName)) {
      throw ArgumentError('Некорректный идентификатор Android-приложения');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString('external_package_$id', packageName);
  }

  static Future<String?> externalPackageName(String id) async {
    if (!id.startsWith('external-') || !isValidProjectId(id)) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('external_package_$id');
    return name != null && isValidAndroidPackageName(name) ? name : null;
  }

  /// Bind installation to the expected Android package whenever known.
  /// Public GitHub repositories are not proof of APK package identity.
  static Future<String?> expectedAndroidPackageName(String id) async {
    if (!isValidProjectId(id)) return null;
    if (id == 'all-hub') return 'com.example.all_hub';
    return packages[id] ?? await externalPackageName(id);
  }

  /// Serialize installs so repeated taps cannot race on staging/backup files.
  static String? _installationInProgress;

  static Future<T> runInstallExclusive<T>(
      String projectId, Future<T> Function() operation) async {
    if (!isValidProjectId(projectId)) {
      throw ArgumentError('Некорректный идентификатор проекта');
    }
    if (_installationInProgress != null) {
      throw StateError('Другая установка уже выполняется: $_installationInProgress');
    }
    _installationInProgress = projectId;
    try {
      return await operation();
    } finally {
      _installationInProgress = null;
    }
  }

  static final ValueNotifier<double?> downloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String?> activeDownloadProject = ValueNotifier<String?>(null);
  static Future<void> recordInstalledVersion(String id, String? version) async {
    if (version == null || version.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('installed_version_$id', version);
  }
  /// An old version receipt alone does not prove the Windows executable
  /// still exists. Keep the receipt for recovery, but show "Install" if the
  /// registered EXE has been moved or deleted.
  static Future<String?> installedWindowsVersion(String id) async {
    if (!isValidProjectId(id)) return null;
    final prefs = await SharedPreferences.getInstance();
    final executable = prefs.getString('exe_$id');
    final version = prefs.getString('installed_version_$id');
    if (executable == null || executable.isEmpty ||
        version == null || version.isEmpty) {
      return null;
    }
    try {
      return await File(executable).exists() ? version : null;
    } on FileSystemException {
      return null;
    }
  }

  static Future<String?> installedVersion(String id) async {
    if (Platform.isAndroid) {
      // The launcher itself is not an external launchable project, but its
      // installed Android version must still be shown in the update catalog.
      final packageName = id == 'all-hub' ? 'com.example.all_hub' :
          (packages[id] ?? await externalPackageName(id));
      if (packageName == null) return null;
      try {
        return await _channel.invokeMethod<String>('installedPackageVersion', {'packageName': packageName});
      } catch (_) { return null; }
    }
    if (Platform.isWindows) {
      // All Hub is the running executable, not a child app under projects/.
      // Never require exe_all-hub to be manually bound to detect its version.
      if (id == 'all-hub') {
        final info = await PackageInfo.fromPlatform();
        return info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
      }
      return installedWindowsVersion(id);
    }
    return null;
  }
  /// Never activate a Windows EXE/ZIP after a short HTTP response. A file
  /// may still have an MZ header even when its body is truncated.
  static void requireCompleteWindowsDownload(int received, int? expected) {
    if (received < 0 || expected != null &&
        (expected < 0 || received != expected)) {
      throw const FormatException('Загрузка Windows-файла завершилась не полностью');
    }
  }

  /// Stream a response to disk for Windows installers and archives.
  static Future<void> _download(http.StreamedResponse response, File file, {int? maxBytes}) async {
    if (maxBytes != null && response.contentLength != null &&
        !isSafeWindowsDownloadBudget(0, response.contentLength!, maxBytes: maxBytes)) {
      throw const FormatException('Windows ZIP слишком большой');
    }
    final sink = file.openWrite();
    var received = 0;
    downloadProgress.value = 0;
    try {
      await for (final bytes in response.stream) {
        if (maxBytes != null &&
            !isSafeWindowsDownloadBudget(received, bytes.length, maxBytes: maxBytes)) {
          throw const FormatException('Windows ZIP слишком большой');
        }
        sink.add(bytes);
        received += bytes.length;
        if (response.contentLength != null && response.contentLength! > 0) {
          downloadProgress.value =
              (received / response.contentLength!).clamp(0.0, 1.0);
        }
      }
      await sink.flush();
      requireCompleteWindowsDownload(received, response.contentLength);
      downloadProgress.value = 1;
    } finally {
      await sink.close();
    }
  }

  /// Download with resumable HTTP Range requests. GitHub release asset links
  /// redirect to short-lived URLs, so each retry starts at the public URL.
  @visibleForTesting
  static Future<void> downloadResumableApk(
    http.Client client, Uri uri, File temporary,
  ) async {
    const maxAttempts = 5;
    int? totalLength;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final existing = await temporary.exists() ? await temporary.length() : 0;
      final request = http.Request('GET', uri);
      if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
      try {
        final response = await client.send(request)
            .timeout(const Duration(seconds: 40));
        if (response.statusCode == 416 && existing > 0) {
          // GitHub rolling releases can replace an APK at the same URL.
          // An old partial file may then be longer than the new asset.
          // HTTP 416 means our saved Range cannot be resumed. Restart from
          // byte zero rather than retrying the same invalid Range five times.
          await response.stream.drain<void>();
          await temporary.delete();
          downloadProgress.value = 0;
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException('Ошибка скачивания: HTTP ${response.statusCode}');
        }
        final isPartial = response.statusCode == 206;
        if (isPartial) {
          final range = response.headers['content-range'];
          if (!isSafeApkContentRange(range, existing)) {
            throw const FormatException('Сервер вернул неверный диапазон APK');
          }
          totalLength = int.parse(range!.substring(range.lastIndexOf('/') + 1));
        } else {
          totalLength = response.contentLength;
        }
        if (totalLength != null && totalLength > 256 * 1024 * 1024) {
          throw const FormatException('APK превышает ограничение 256 МиБ');
        }
        final sink = temporary.openWrite(
          mode: isPartial ? FileMode.append : FileMode.write,
        );
        var received = isPartial ? existing : 0;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 45),
          )) {
            if (!isSafeWindowsDownloadBudget(received, chunk.length)) {
              throw const FormatException('APK превышает ограничение 256 МиБ');
            }
            sink.add(chunk);
            received += chunk.length;
            if (totalLength != null && totalLength > 0) {
              downloadProgress.value =
                  (received / totalLength).clamp(0.0, 1.0);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        final actual = await temporary.length();
        if (totalLength != null && actual < totalLength) {
          throw const HttpException('Соединение оборвалось до конца APK');
        }
        if (totalLength != null && actual > totalLength) {
          throw const FormatException('Размер APK превышает ожидаемый');
        }
        downloadProgress.value = 1;
        return;
      } catch (_) {
        if (attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
  }

  static const _channel = MethodChannel('allhub/launcher');
  static const packages = <String, String>{
    'shadow-rp': 'com.shadowrp.app',
    'kopilka': 'com.veyrion.kopilka_app',
    'eclipse-arena': 'org.eclipsearena.prototype',
    'nova-game': 'com.perchikhot.novagame',
  };

  static Future<bool> isAvailable(String id) async {
    if (Platform.isAndroid) {
      final packageName = packages[id] ?? await externalPackageName(id);
      if (packageName == null) return false;
      try {
        return await _channel.invokeMethod<bool>(
          'isPackageInstalled', {'packageName': packageName}) ?? false;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      final executable = prefs.getString('exe_$id');
      return executable != null && await File(executable).exists();
    }
    return false;
  }

  static Future<bool> launch(String id) async {
    if (Platform.isAndroid) {
      final packageName = packages[id] ?? await externalPackageName(id);
      if (packageName == null) return false;
      return await _channel.invokeMethod<bool>('launchPackage', {'packageName': packageName}) ?? false;
    }
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      final executable = prefs.getString('exe_$id');
      if (executable == null || !await File(executable).exists()) return false;
      // A successful CreateProcess call is not proof that the new release
      // actually starts. Detect immediate crashes (missing DLLs, invalid
      // bundled assets, etc.) before committing the version receipt.
      final process = await Process.start(executable, [],
          mode: ProcessStartMode.normal,
          workingDirectory: File(executable).parent.path);
      final earlyExit = await Future.any<bool>([
        process.exitCode.then((code) => true),
        Future<bool>.delayed(const Duration(seconds: 3), () => false),
      ]);
      if (earlyExit) {
        throw StateError('Windows-приложение завершилось сразу после запуска; обновление отменено');
      }
      return true;
    }
    return false;
  }

  /// Install and launch a Windows release as one transaction. If Windows
  /// rejects the new executable, restore the previous launch target and
  /// version receipt so the user can still open the working installation.
  /// Old release files are intentionally retained for rollback.
  static Future<void> updateAndLaunchWindows(
    String id, String url, {
    String? version,
    String? externalRepo,
    String? sha256Digest,
  }) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    if (!isValidProjectId(id) || id == 'all-hub') {
      throw ArgumentError('Самообновление All Hub требует отдельного установщика');
    }
    await runInstallExclusive(id, () async {
      final prefs = await SharedPreferences.getInstance();
      final previousExe = prefs.getString('exe_$id');
      final previousVersion = prefs.getString('installed_version_$id');
      var installed = false;
      try {
        final path = Uri.parse(url).path.toLowerCase();
        if (path.endsWith('.zip')) {
          await installWindowsZip(id, url,
              externalRepo: externalRepo, sha256Digest: sha256Digest);
        } else if (path.endsWith('.exe')) {
          await installWindowsExe(id, url,
              externalRepo: externalRepo, sha256Digest: sha256Digest);
        } else {
          throw StateError('Формат обновления Windows не поддерживается');
        }
        installed = true;
        if (!await launch(id)) {
          throw StateError('Windows не удалось запустить обновлённое приложение');
        }
        await recordInstalledVersion(id, version);
      } catch (_) {
        if (installed) {
          if (previousExe == null) {
            await prefs.remove('exe_$id');
          } else {
            await prefs.setString('exe_$id', previousExe);
          }
          if (previousVersion == null) {
            await prefs.remove('installed_version_$id');
          } else {
            await prefs.setString('installed_version_$id', previousVersion);
          }
        }
        rethrow;
      }
    });
  }

  /// Reconcile a pending handoff on startup. The new launcher confirms the
  /// receipt only after Flutter has initialized; a fallback to the previous
  /// executable restores the old receipt instead of claiming an update.
  static Future<void> reconcileAllHubWindowsHandoff() async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    final next = prefs.getString('allhub_pending_exe');
    if (next == null) return;
    final current = File(Platform.resolvedExecutable).absolute.path.toLowerCase();
    final expected = File(next).absolute.path.toLowerCase();
    final previous = prefs.getString('allhub_previous_exe');
    final previousVersion = prefs.getString('allhub_previous_version');
    // The external updater writes a failure receipt before launching the old
    // binary. A previous app must never leave the failed new version registered.
    final failed = File('$next.failed');
    if (await failed.exists() && previous != null &&
        current == File(previous).absolute.path.toLowerCase()) {
      await prefs.setString('exe_all-hub', previous);
      if (previousVersion == null) {
        await prefs.remove('installed_version_all-hub');
      } else {
        await prefs.setString('installed_version_all-hub', previousVersion);
      }
      await prefs.setString('allhub_last_update_error',
          (await failed.readAsString()).trim());
      await failed.delete();
      for (final key in [
        'allhub_pending_exe', 'allhub_pending_version',
        'allhub_previous_exe', 'allhub_previous_version',
      ]) {
        await prefs.remove(key);
      }
      return;
    }
    if (current == expected) {
      await prefs.setString('exe_all-hub', next);
      final version = prefs.getString('allhub_pending_version');
      if (version != null && version.isNotEmpty) {
        await prefs.setString('installed_version_all-hub', version);
      }
    } else if (previous != null &&
        current == File(previous).absolute.path.toLowerCase()) {
      await prefs.setString('exe_all-hub', previous);
      if (previousVersion == null) {
        await prefs.remove('installed_version_all-hub');
      } else {
        await prefs.setString('installed_version_all-hub', previousVersion);
      }
    } else {
      // Do not clear a pending transaction for an unrelated executable.
      return;
    }
    // Keep the rollback receipt until the external updater has observed a
    // stable process. Otherwise an early crash leaves the old launcher unable
    // to restore the previous registered version.
    final committed = File('$next.committed');
    if (current == expected && !await committed.exists()) {
      await File('$next.confirmed').writeAsString('ready', flush: true);
      return;
    }
    for (final key in [
      'allhub_pending_exe', 'allhub_pending_version',
      'allhub_previous_exe', 'allhub_previous_version',
    ]) {
      await prefs.remove(key);
    }
    if (current == expected && await committed.exists()) {
      await committed.delete();
    }
  }

  /// Stage the launcher side-by-side, then hand off activation to a separate
  /// Windows process. The old running EXE is never overwritten or deleted.
  /// This is intentionally not a shortcut migration: existing shortcuts may
  /// still point at the previous launcher until a stable bootstrapper is added.
  static Future<void> updateAllHubWindows(
    String url, {String? version, String? sha256Digest}
  ) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    await runInstallExclusive('all-hub', () async {
      final prefs = await SharedPreferences.getInstance();
      final previousExe = prefs.getString('exe_all-hub');
      final previousVersion = prefs.getString('installed_version_all-hub');
      try {
        final extension = Uri.parse(url).path.toLowerCase();
        // Flutter Windows applications are not standalone EXEs: they require
        // flutter_windows.dll, data/flutter_assets and plugin DLLs. Never
        // replace the running launcher with a bare EXE from a release.
        if (!extension.endsWith('.zip')) {
          throw StateError(
              'Для самообновления All Hub нужен полный Windows ZIP с DLL и ресурсами');
        }
        await installWindowsZip('all-hub', url, sha256Digest: sha256Digest);
        final nextExe = prefs.getString('exe_all-hub');
        if (nextExe == null || !await File(nextExe).exists()) {
          throw StateError('Новая версия лаунчера не найдена');
        }
        // Check the complete Flutter runtime before asking the old process
        // to exit. A valid PE header alone cannot detect missing dependencies.
        final bundle = File(nextExe).parent;
        final runtime = File('${bundle.path}${Platform.pathSeparator}flutter_windows.dll');
        final assets = Directory(
            '${bundle.path}${Platform.pathSeparator}data'
            '${Platform.pathSeparator}flutter_assets');
        final icu = File('${bundle.path}${Platform.pathSeparator}data'
            '${Platform.pathSeparator}icudtl.dat');
        if (!await runtime.exists() || !await assets.exists() ||
            !await icu.exists()) {
          throw StateError(
              'Windows ZIP неполный: отсутствуют Flutter DLL, assets или ICU');
        }
        // The installer stages a release by writing exe_all-hub. That is not
        // activation: keep the current launcher registered until the new
        // process confirms startup in reconcileAllHubWindowsHandoff().
        // A failed or never-started helper must not leave a phantom install.
        if (previousExe == null) {
          await prefs.remove('exe_all-hub');
        } else {
          await prefs.setString('exe_all-hub', previousExe);
        }
        // Process.start is independent of the running Flutter application.
        // Validate the executable before requesting the current process exit.
        final handle = await File(nextExe).open();
        try {
          if (!hasWindowsExecutableHeader(await handle.read(8192))) {
            throw const FormatException('Новая версия All Hub не является Windows EXE');
          }
        } finally {
          await handle.close();
        }
        // Remove any stale receipt from a previous attempted launch before
        // starting the helper; otherwise it could accept a false success.
        final confirmation = File('$nextExe.confirmed');
        if (await confirmation.exists()) await confirmation.delete();
        final committed = File('$nextExe.committed');
        if (await committed.exists()) await committed.delete();
        final failed = File('$nextExe.failed');
        if (await failed.exists()) await failed.delete();
        await prefs.remove('allhub_last_update_error');
        // PowerShell's argument list is passed as individual arguments, never
        // through a shell command assembled from an untrusted release URL.
        // The helper waits for the current process to finish, then starts the
        // staged launcher in its own working directory.
        final script = r'''
param([int]$OldPid, [string]$NextExe, [string]$PreviousExe, [string]$SupportRoot)
$ErrorActionPreference = 'Stop'
try { Wait-Process -Id $OldPid -ErrorAction SilentlyContinue } catch {}
if (-not (Test-Path -LiteralPath $NextExe -PathType Leaf)) { exit 2 }
try {
  $newProcess = Start-Process -FilePath $NextExe -WorkingDirectory (Split-Path -Parent $NextExe) -PassThru
  # Do not migrate shortcuts until Flutter confirms its installed-version
  # receipt has been persisted. Timeout or early exit triggers rollback.
  $confirmed = "$NextExe.confirmed"
  $deadline = (Get-Date).AddSeconds(60)
  while (-not (Test-Path -LiteralPath $confirmed -PathType Leaf)) {
    $newProcess.Refresh()
    if ($newProcess.HasExited) { throw 'New launcher exited before confirming startup' }
    if ((Get-Date) -ge $deadline) { throw 'New launcher did not confirm startup' }
    Start-Sleep -Milliseconds 500
  }
  # A receipt written during startup is not enough if the UI immediately
  # crashes. Observe a short post-confirmation window before moving shortcuts.
  $stableUntil = (Get-Date).AddSeconds(8)
  while ((Get-Date) -lt $stableUntil) {
    $newProcess.Refresh()
    if ($newProcess.HasExited) { throw 'New launcher exited after startup confirmation' }
    Start-Sleep -Milliseconds 500
  }
  # The update is not committed until the stable launcher pointer has
  # been installed. Otherwise a shortcut/pointer failure can roll back the
  # old executable while the new process later accepts a false commit.
  # Stable entry point: shortcuts must never point at an immutable release EXE.
  # Store the pointer outside version folders so future updates only change
  # this pointer. A failed handoff leaves the previous pointer untouched.
  $supportRoot = $SupportRoot
  $entry = Join-Path $supportRoot 'AllHub-Launch.cmd'
  $pointer = Join-Path $supportRoot 'AllHub-Current.txt'
  $entryContent = @'
@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0AllHub-Launch.ps1"
'@
  $launchScript = @'
$ErrorActionPreference = 'Stop'
$pointer = Join-Path $PSScriptRoot 'AllHub-Current.txt'
$backup = Join-Path $PSScriptRoot 'AllHub-Previous.txt'
# A broken or deleted release must not strand the user behind a dead shortcut.
# Never execute arbitrary command lines: both pointer files contain only paths
# to previously installed EXEs, and Start-Process receives a literal path.
foreach ($file in @($pointer, $backup)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
  $target = (Get-Content -LiteralPath $file -Encoding UTF8 -TotalCount 1).Trim()
  if (-not $target -or -not [IO.Path]::IsPathRooted($target) -or
      -not $target.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
  # A Flutter Windows build needs its runtime beside the EXE. A valid
  # executable alone is not enough: missing DLL/assets cause a dead shortcut.
  $bundle = Split-Path -Parent $target
  if (-not (Test-Path -LiteralPath (Join-Path $bundle 'flutter_windows.dll') -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $bundle 'data\\icudtl.dat') -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $bundle 'data\\flutter_assets') -PathType Container)) { continue }
  try {
    $process = Start-Process -FilePath $target -WorkingDirectory $bundle -PassThru -ErrorAction Stop
    # Start-Process succeeding does not mean Flutter actually started. If it
    # crashes immediately, try the last known-good build instead.
    if ($process.WaitForExit(3000)) {
      if ($process.ExitCode -ne 0) { continue }
    }
    exit 0
  } catch { continue }
}
exit 4
'@
  Set-Content -LiteralPath (Join-Path $supportRoot 'AllHub-Launch.ps1') -Value $launchScript -Encoding UTF8
  # Install the stable entry before updating the pointer. No executable is
  # ever modified while running; the .cmd lives in application support.
  Set-Content -LiteralPath $entry -Value $entryContent -Encoding ASCII
  # Retain a known-good executable for the stable launcher if a release
  # folder is removed after an otherwise successful update.
  if ($PreviousExe -and (Test-Path -LiteralPath $PreviousExe -PathType Leaf)) {
    Set-Content -LiteralPath (Join-Path $supportRoot 'AllHub-Previous.txt') -Value $PreviousExe -Encoding UTF8
  }
  $pendingPointer = "$pointer.new"
  Set-Content -LiteralPath $pendingPointer -Value $NextExe -Encoding UTF8
  Move-Item -LiteralPath $pendingPointer -Destination $pointer -Force
  # A user launching via the stable entry always gets the confirmed build.
  # Create a durable user shortcut even for portable installations that
  # never had an existing shortcut to migrate. Do not overwrite user links.
  $shell = New-Object -ComObject WScript.Shell
  $userLinks = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'All Hub.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'All Hub.lnk')
  )
  foreach ($link in $userLinks) {
    try {
      $parent = Split-Path -Parent $link
      if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { continue }
      if (Test-Path -LiteralPath $link) { continue }
      $shortcut = $shell.CreateShortcut($link)
      $shortcut.TargetPath = $entry
      $shortcut.WorkingDirectory = $supportRoot
      $shortcut.Description = 'All Hub — запуск актуальной версии'
      $shortcut.Save()
    } catch {
      # Shortcuts are optional; failure must not roll back a healthy update.
    }
  }
  # Commit only after the durable entry point and pointer are installed.
  # Shortcut migration is best-effort and must not block a healthy launch.
  Set-Content -LiteralPath "$NextExe.committed" -Value 'stable'
  # Existing shortcuts pointing to a previous EXE are migrated below.
} catch {
  # Never let a stale success receipt win over a failed activation.
  try { Remove-Item -LiteralPath "$NextExe.committed" -Force -ErrorAction SilentlyContinue } catch {}
  # Persist the failure independently of the new process. The old launcher
  # reconciles this marker on startup and restores its version receipt.
  try { Set-Content -LiteralPath "$NextExe.failed" -Value $_.Exception.Message } catch {}
  # If the stable pointer was changed before a later failure, restore it.
  try {
    if ($PreviousExe -and (Test-Path -LiteralPath $PreviousExe -PathType Leaf)) {
      $pointer = Join-Path $SupportRoot 'AllHub-Current.txt'
      Set-Content -LiteralPath "$pointer.rollback" -Value $PreviousExe -Encoding UTF8
      Move-Item -LiteralPath "$pointer.rollback" -Destination $pointer -Force
    }
  } catch {}
  if ($PreviousExe -and (Test-Path -LiteralPath $PreviousExe -PathType Leaf)) {
    try { Start-Process -FilePath $PreviousExe -WorkingDirectory (Split-Path -Parent $PreviousExe) } catch {}
  }
  exit 3
}
# Migrate only shortcuts that explicitly target the previous launcher.
# Do not alter unrelated shortcuts or system-wide shortcuts.
if ($PreviousExe -and ($PreviousExe -ne $NextExe)) {
  try {
    $shell = New-Object -ComObject WScript.Shell
    $roots = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('StartMenu'))
    foreach ($root in $roots) {
      if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
      Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          $shortcut = $shell.CreateShortcut($_.FullName)
          if ([string]::Equals($shortcut.TargetPath, $PreviousExe, [StringComparison]::OrdinalIgnoreCase) -or
              [string]::Equals($shortcut.TargetPath, $NextExe, [StringComparison]::OrdinalIgnoreCase)) {
            $shortcut.TargetPath = $entry
            $shortcut.WorkingDirectory = $supportRoot
            $shortcut.Save()
          }
        } catch {}
      }
    }
  } catch {}
}
''';
        final helper = File('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}allhub-handoff-${DateTime.now().microsecondsSinceEpoch}.ps1');
        await helper.writeAsString(script, flush: true);
        // Record a recoverable transaction, not a successful installation.
        // The new process commits it during startup; the old process restores
        // the receipt if the external updater has to fall back.
        // Rollback must point to the executable actually running, even if a
        // stale preference points to a different historical installation.
        await prefs.setString('allhub_previous_exe', Platform.resolvedExecutable);
        if (previousVersion == null) {
          await prefs.remove('allhub_previous_version');
        } else {
          await prefs.setString('allhub_previous_version', previousVersion);
        }
        await prefs.setString('allhub_pending_exe', nextExe);
        if (version == null) {
          await prefs.remove('allhub_pending_version');
        } else {
          await prefs.setString('allhub_pending_version', version);
        }
        await Process.start('powershell.exe', [
          '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
          '-File', helper.path, '-OldPid', pid.toString(),
          '-NextExe', nextExe,
          '-PreviousExe', Platform.resolvedExecutable,
          '-SupportRoot', (await getApplicationSupportDirectory()).path,
        ], mode: ProcessStartMode.detached);
        // Do not claim the update succeeded before the new launcher starts.
        // The caller must close the current Flutter process after success.
      } catch (_) {
        if (previousExe == null) {
          await prefs.remove('exe_all-hub');
        } else {
          await prefs.setString('exe_all-hub', previousExe);
        }
        if (previousVersion == null) {
          await prefs.remove('installed_version_all-hub');
        } else {
          await prefs.setString('installed_version_all-hub', previousVersion);
        }
        rethrow;
      }
    });
  }

  /// Check GitHub's published SHA-256 digest before activating an installer.
  /// Older releases without a digest retain existing container checks.
  static Future<void> verifyDownloadedDigest(File file, String? expected) async {
    if (expected == null) {
      return;
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const FormatException('Некорректная контрольная сумма SHA-256');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      throw const FormatException('SHA-256 файла не совпадает с GitHub Releases');
    }
  }

  /// A system installer intent being launched is NOT proof of installation,
  /// but false/null must be surfaced instead of marking the update successful.
  static void requireAndroidInstallerOpened(bool? opened) {
    if (opened != true) {
      throw StateError('Не удалось открыть системный установщик Android');
    }
  }

  /// Downloads a published APK directly, then asks Android to install it.
  /// Android always requires user confirmation; this cannot silently install apps.
  static Future<void> installAndroidApk(String url, {String? projectId, String? externalRepo, String? sha256Digest}) async {
    if (!Platform.isAndroid) throw UnsupportedError('Android only');
    final uri = Uri.tryParse(url);
    if (uri == null || projectId == null ||
        !(externalRepo == null
            ? isTrustedProjectDownload(projectId, url, 'apk')
            : isTrustedExternalDownload(projectId, externalRepo, url, 'apk'))) {
      throw ArgumentError('Нужна прямая ссылка на APK из GitHub Releases');
    }
    activeDownloadProject.value = projectId;
    downloadProgress.value = null;
    final client = http.Client();
    try {
      final cache = await getTemporaryDirectory();
      final cacheName = externalRepo == null
          ? androidApkCacheName(projectId, url)
          : ('${projectId}_${uri.pathSegments[4]}_${uri.pathSegments[5]}')
              .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final apk = File('${cache.path}${Platform.pathSeparator}$cacheName');
      final temporary = File('${apk.path}.download');
      try {
        downloadProgress.value = 0;
        await downloadResumableApk(client, uri, temporary);
        if (await temporary.length() < 1024) {
          throw const FormatException('APK слишком мал');
        }
        final file = await temporary.open();
        try {
          final header = await file.read(4);
          if (header.length != 4 || header[0] != 0x50 || header[1] != 0x4b ||
              header[2] != 0x03 || header[3] != 0x04) {
            throw const FormatException('Скачан не APK (не ZIP-контейнер)');
          }
        } finally {
          await file.close();
        }
        // Rolling GitHub Releases replace the asset at the same URL. A partial
        // download from the previous asset must never be resumed into the new
        // APK. On a digest mismatch, discard the partial file and retry once
        // from byte zero; never bypass SHA-256 verification.
        try {
          await verifyDownloadedDigest(temporary, sha256Digest);
        } on FormatException {
          if (sha256Digest == null) rethrow;
          if (await temporary.exists()) await temporary.delete();
          downloadProgress.value = 0;
          await downloadResumableApk(client, uri, temporary);
          await verifyDownloadedDigest(temporary, sha256Digest);
        }
        if (await apk.exists()) await apk.delete();
        await temporary.rename(apk.path);
        // Android owns the final install confirmation. A false/null result
        // means the system installer could not even be opened; never report
        // that as a successful update.
        final expectedPackage = await expectedAndroidPackageName(projectId);
        final opened = await _channel.invokeMethod<bool>(
          'installApk', {
            'path': apk.path,
            if (expectedPackage != null) 'expectedPackageName': expectedPackage,
          });
        requireAndroidInstallerOpened(opened);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      client.close();
      downloadProgress.value = null;
      activeDownloadProject.value = null;
    }
  }

  static void requireWindowsInstallRegistered(bool saved) {
    if (!saved) throw StateError('Не удалось сохранить путь установленного Windows-приложения');
  }

  // Installs a standalone Windows EXE from a published GitHub release.
  // Portable ZIP distributions require their full folder and are not handled here.
  static Future<void> installWindowsExe(String id, String url, {String? externalRepo, String? sha256Digest}) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    if (!isValidProjectId(id)) {
      throw ArgumentError('Некорректный идентификатор проекта');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(externalRepo == null
        ? isTrustedProjectDownload(id, url, 'exe')
        : isTrustedExternalDownload(id, externalRepo, url, 'exe'))) {
      throw ArgumentError('Нужна прямая ссылка на EXE из GitHub Releases');
    }
    activeDownloadProject.value = id;
    downloadProgress.value = null;
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Ошибка скачивания: HTTP ${response.statusCode}');
      }
      final root = await getApplicationSupportDirectory();
      final projects = Directory('${root.path}${Platform.pathSeparator}projects');
      await projects.create(recursive: true);
      // A running Windows EXE cannot be renamed or overwritten. Install each
      // published standalone build into its own immutable version directory,
      // just as we do for portable ZIP releases. The registered launcher path
      // is switched only after the download and PE/digest checks succeed.
      final releaseFolder = windowsReleaseFolder(
          id, url, DateTime.now().microsecondsSinceEpoch);
      final targetDirectory =
          Directory('${projects.path}${Platform.pathSeparator}$releaseFolder');
      final staging = Directory('${targetDirectory.path}.staging');
      final temporary = File('${projects.path}${Platform.pathSeparator}$releaseFolder.download');
      try {
        await _download(response, temporary, maxBytes: 256 * 1024 * 1024);
        if (await temporary.length() < 1024) {
          throw const FormatException('Загруженный EXE слишком мал');
        }
        final file = await temporary.open();
        try {
          if (!hasWindowsExecutableHeader(await file.read(8192))) {
            throw const FormatException('Файл не является корректным Windows PE (MZ/PE)');
          }
        } finally {
          await file.close();
        }
        await verifyDownloadedDigest(temporary, sha256Digest);
        await staging.create(recursive: true);
        final stagedExe = File('${staging.path}${Platform.pathSeparator}$id.exe');
        await temporary.rename(stagedExe.path);
        await staging.rename(targetDirectory.path);
        try {
          final prefs = await SharedPreferences.getInstance();
          requireWindowsInstallRegistered(await prefs.setString(
              'exe_$id', '${targetDirectory.path}${Platform.pathSeparator}$id.exe'));
        } catch (_) {
          // Keep the previous registered EXE untouched on preferences failure.
          if (await targetDirectory.exists()) {
            await targetDirectory.delete(recursive: true);
          }
          rethrow;
        }
      } finally {
        if (await temporary.exists()) await temporary.delete();
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    } finally {
      client.close();
      downloadProgress.value = null;
      activeDownloadProject.value = null;
    }
  }

  /// Different builds must never overwrite a running Windows executable.
  /// A unique generation suffix also makes reinstallation of the same
  /// release safe while an older instance remains open.
  @visibleForTesting
  static String windowsReleaseFolder(String id, String url, int generation) {
    if (!isValidProjectId(id) || generation < 0) {
      throw ArgumentError('Некорректный проект или поколение установки');
    }
    final digest = sha256.convert(url.codeUnits).toString().substring(0, 16);
    return '$id-$digest-$generation';
  }

  /// Install a complete Windows portable ZIP, including runtime DLLs and assets.
  /// Files are extracted to a staging directory and activated only after validation.
  static Future<void> installWindowsZip(String id, String url, {String? externalRepo, String? sha256Digest}) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    if (!isValidProjectId(id)) {
      throw ArgumentError('Некорректный идентификатор проекта');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(externalRepo == null
        ? isTrustedProjectDownload(id, url, 'zip')
        : isTrustedExternalDownload(id, externalRepo, url, 'zip'))) {
      throw ArgumentError('Нужна ссылка на Windows ZIP из GitHub Releases');
    }
    final root = await getApplicationSupportDirectory();
    final projects = Directory('${root.path}${Platform.pathSeparator}projects');
    await projects.create(recursive: true);
    // A running Windows process locks its EXE and Flutter DLLs. Renaming the
    // currently installed directory therefore fails with ACCESS_DENIED.
    // Install each release side-by-side and atomically switch the registered
    // launcher path only after validation. The running old version remains
    // usable until the user launches the new one; never delete its files.
    // Keep old releases for rollback and for apps that store data beside EXE.
    final releaseFolder = windowsReleaseFolder(
        id, url, DateTime.now().microsecondsSinceEpoch);
    final target = Directory('${projects.path}${Platform.pathSeparator}$releaseFolder');
    final staging = Directory('${target.path}.staging');
    final zipFile = File('${projects.path}${Platform.pathSeparator}$releaseFolder.download.zip');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    activeDownloadProject.value = id;
    downloadProgress.value = null;
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Ошибка скачивания: HTTP ${response.statusCode}');
      }
      await _download(response, zipFile, maxBytes: 256 * 1024 * 1024);
      if (await zipFile.length() > 256 * 1024 * 1024) {
        throw const FormatException('Windows ZIP слишком большой');
      }
      await verifyDownloadedDigest(zipFile, sha256Digest);
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      if (!isSafeWindowsArchiveLayout(
        archive.where((entry) => entry.isFile).map((entry) => entry.name),
        archive.where((entry) => !entry.isFile).map((entry) => entry.name),
      )) {
        throw const FormatException('ZIP содержит конфликтующие пути файлов');
      }
      final rootPath = staging.absolute.path;
      var unpackedBytes = 0;
      var entriesSeen = 0;
      for (final entry in archive) {
        entriesSeen++;
        if (!isSafeWindowsArchiveBudget(entriesSeen, unpackedBytes, entry.size)) {
          throw const FormatException('ZIP превышает безопасный размер распаковки');
        }
        unpackedBytes += entry.size;
        final name = entry.name.replaceAll('\\', '/');
        if (!isSafeWindowsArchivePath(name)) {
          throw const FormatException('Недопустимый путь в ZIP');
        }
        if (name.isEmpty) continue;
        final destination = '$rootPath${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}';
        if (entry.isFile) {
          final file = File(destination);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.content as List<int>, flush: true);
        } else {
          await Directory(destination).create(recursive: true);
        }
      }
      final executables = await staging.list(recursive: true).where(
        (entity) => entity is File && entity.path.toLowerCase().endsWith('.exe'),
      ).cast<File>().toList();
      if (executables.isEmpty) {
        throw const FormatException('В архиве нет исполняемого EXE');
      }
      // A ZIP can contain arbitrary files named .exe. Reject an invalid
      // launcher before activating the staging directory, preserving the
      // previous installation and its settings.
      for (final executable in executables) {
        final handle = await executable.open();
        try {
          if (!hasWindowsExecutableHeader(await handle.read(8192))) {
            throw const FormatException('ZIP содержит некорректный Windows EXE');
          }
        } finally {
          await handle.close();
        }
      }
      final relativeExe = selectWindowsLaunchExecutable(id,
          executables.map((exe) => exe.path.substring(staging.path.length)));
      if (relativeExe == null) {
        throw const FormatException(
            'В Windows ZIP несколько EXE без однозначного приложения');
      }
      // Validate Flutter projects before registration; Godot and native
      // Windows games use different layouts and must not be rejected.
      if (id == 'all-hub' || id == 'kopilka') {
      final launchFile = File('${staging.path}$relativeExe');
      final bundleRoot = launchFile.parent;
      final runtimeDll = File('${bundleRoot.path}${Platform.pathSeparator}flutter_windows.dll');
      final flutterAssets = Directory('${bundleRoot.path}${Platform.pathSeparator}data'
          '${Platform.pathSeparator}flutter_assets');
      final icuData = File('${bundleRoot.path}${Platform.pathSeparator}data'
          '${Platform.pathSeparator}icudtl.dat');
      if (!await runtimeDll.exists() || !await flutterAssets.exists() ||
          !await icuData.exists()) {
        throw const FormatException(
            'Windows ZIP неполный: отсутствуют Flutter DLL, assets или ICU');
      }
      // Empty asset directories are not usable Flutter installations.
      if (await flutterAssets.list(followLinks: false).isEmpty) {
        throw const FormatException('Windows ZIP содержит пустой flutter_assets');
      }
      }
      // Publish only a fully unpacked and validated directory. No running
      // EXE is overwritten, and the old registered path stays valid if this
      // operation fails. This is also safe while the old game is still open.
      try {
        await staging.rename(target.path);
        final prefs = await SharedPreferences.getInstance();
        requireWindowsInstallRegistered(
            await prefs.setString('exe_$id', '${target.path}$relativeExe'));
      } catch (_) {
        if (await target.exists()) await target.delete(recursive: true);
        rethrow;
      }
    } finally {
      client.close();
      downloadProgress.value = null;
      activeDownloadProject.value = null;
      if (await zipFile.exists()) await zipFile.delete();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static Future<bool> configureWindowsExecutable(String id) async {
    if (!Platform.isWindows) return false;
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['exe']);
    final path = selection?.files.single.path;
    if (path == null || !path.toLowerCase().endsWith('.exe')) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString('exe_$id', path);
  }

  static bool canLaunch(String id) => Platform.isWindows ||
      (Platform.isAndroid &&
          (packages.containsKey(id) || id.startsWith('external-')));
}
