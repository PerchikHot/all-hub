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
    final uri = Uri.tryParse(url);
    if (repo == null || !['apk', 'exe', 'zip'].contains(extension) ||
        uri == null || uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
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

  /// Check a portable EXE before replacing a previously working installation.
  static bool hasWindowsExecutableHeader(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x4d && bytes[1] == 0x5a;

  // Project IDs become Windows directory names: never accept path segments.
  static bool isValidProjectId(String id) =>
      RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id);
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
      totalBytes + nextEntryBytes <= 1024 * 1024 * 1024;

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

  static final ValueNotifier<double?> downloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String?> activeDownloadProject = ValueNotifier<String?>(null);
  static Future<void> recordInstalledVersion(String id, String? version) async {
    if (version == null || version.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('installed_version_$id', version);
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('installed_version_$id');
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
      downloadProgress.value = 1;
    } finally {
      await sink.close();
    }
  }

  /// Download with resumable HTTP Range requests. GitHub release asset links
  /// redirect to short-lived URLs, so each retry starts at the public URL.
  static Future<void> _downloadResumable(
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
      await Process.start(executable, [], mode: ProcessStartMode.detached,
          workingDirectory: File(executable).parent.path);
      return true;
    }
    return false;
  }

  /// Check GitHub's published SHA-256 digest before activating an installer.
  /// Older releases without a digest retain existing container checks.
  static Future<void> verifyDownloadedDigest(File file, String? expected) async {
    if (expected == null) return;
    if (!RegExp(r'^[a-f0-9]{64}
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
        await _downloadResumable(client, uri, temporary);
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
        await verifyDownloadedDigest(temporary, sha256Digest);
        if (await apk.exists()) await apk.delete();
        await temporary.rename(apk.path);
        await _channel.invokeMethod<bool>('installApk', {'path': apk.path});
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      client.close();
      downloadProgress.value = null;
      activeDownloadProject.value = null;
    }
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
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Ошибка скачивания: HTTP ${response.statusCode}');
      }
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id');
      await directory.create(recursive: true);
      final target = File('${directory.path}${Platform.pathSeparator}$id.exe');
      final temporary = File('${target.path}.download');
      try {
        // Apply the same streaming size limit to standalone EXEs as to ZIPs.
        // A server with a missing Content-Length must not fill the disk.
        await _download(response, temporary, maxBytes: 256 * 1024 * 1024);
        if (await temporary.length() < 1024) {
          throw const FormatException('Загруженный EXE слишком мал');
        }
        final file = await temporary.open();
        try {
          final header = await file.read(2);
          if (!hasWindowsExecutableHeader(header)) {
            throw const FormatException('Файл не похож на Windows EXE (нет MZ-заголовка)');
          }
        } finally {
          await file.close();
        }
        await verifyDownloadedDigest(temporary, sha256Digest);
        // Preserve the last working version if the replacement fails.
        final backup = File('${target.path}.backup');
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
        try {
          await temporary.rename(target.path);
          if (await backup.exists()) await backup.delete();
        } catch (_) {
          if (await backup.exists()) await backup.rename(target.path);
          rethrow;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exe_$id', target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      client.close();
    }
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
    final target = Directory('${projects.path}${Platform.pathSeparator}$id');
    final staging = Directory('${projects.path}${Platform.pathSeparator}$id.staging');
    final backup = Directory('${projects.path}${Platform.pathSeparator}$id.backup');
    final zipFile = File('${projects.path}${Platform.pathSeparator}$id.download.zip');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
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
          if (!hasWindowsExecutableHeader(await handle.read(2))) {
            throw const FormatException('ZIP содержит некорректный Windows EXE');
          }
        } finally {
          await handle.close();
        }
      }
      executables.sort((a, b) {
        final aName = a.uri.pathSegments.last.toLowerCase();
        final bName = b.uri.pathSegments.last.toLowerCase();
        final aRank = aName.contains(id.replaceAll('-', '')) ? 0 : 1;
        final bRank = bName.contains(id.replaceAll('-', '')) ? 0 : 1;
        return aRank.compareTo(bRank);
      });
      final relativeExe = executables.first.path.substring(staging.path.length);
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await target.exists()) await target.rename(backup.path);
      try {
        await staging.rename(target.path);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exe_$id', '${target.path}$relativeExe');
        if (await backup.exists()) await backup.delete(recursive: true);
      } catch (_) {
        if (await target.exists()) await target.delete(recursive: true);
        if (await backup.exists()) await backup.rename(target.path);
        rethrow;
      }
    } finally {
      client.close();
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
).hasMatch(expected)) {
      throw const FormatException('Некорректная контрольная сумма SHA-256');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      throw const FormatException('SHA-256 файла не совпадает с GitHub Releases');
    }
  }

  /// Downloads a published APK directly, then asks Android to install it.
  /// Android always requires user confirmation; this cannot silently install apps.
  static Future<void> installAndroidApk(String url, {String? projectId, String? externalRepo}) async {
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
        await _downloadResumable(client, uri, temporary);
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
        if (await apk.exists()) await apk.delete();
        await temporary.rename(apk.path);
        await _channel.invokeMethod<bool>('installApk', {'path': apk.path});
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      client.close();
      downloadProgress.value = null;
      activeDownloadProject.value = null;
    }
  }

  // Installs a standalone Windows EXE from a published GitHub release.
  // Portable ZIP distributions require their full folder and are not handled here.
  static Future<void> installWindowsExe(String id, String url, {String? externalRepo}) async {
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
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Ошибка скачивания: HTTP ${response.statusCode}');
      }
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id');
      await directory.create(recursive: true);
      final target = File('${directory.path}${Platform.pathSeparator}$id.exe');
      final temporary = File('${target.path}.download');
      try {
        // Apply the same streaming size limit to standalone EXEs as to ZIPs.
        // A server with a missing Content-Length must not fill the disk.
        await _download(response, temporary, maxBytes: 256 * 1024 * 1024);
        if (await temporary.length() < 1024) {
          throw const FormatException('Загруженный EXE слишком мал');
        }
        final file = await temporary.open();
        try {
          final header = await file.read(2);
          if (!hasWindowsExecutableHeader(header)) {
            throw const FormatException('Файл не похож на Windows EXE (нет MZ-заголовка)');
          }
        } finally {
          await file.close();
        }
        // Preserve the last working version if the replacement fails.
        final backup = File('${target.path}.backup');
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
        try {
          await temporary.rename(target.path);
          if (await backup.exists()) await backup.delete();
        } catch (_) {
          if (await backup.exists()) await backup.rename(target.path);
          rethrow;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exe_$id', target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      client.close();
    }
  }

  /// Install a complete Windows portable ZIP, including runtime DLLs and assets.
  /// Files are extracted to a staging directory and activated only after validation.
  static Future<void> installWindowsZip(String id, String url, {String? externalRepo}) async {
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
    final target = Directory('${projects.path}${Platform.pathSeparator}$id');
    final staging = Directory('${projects.path}${Platform.pathSeparator}$id.staging');
    final backup = Directory('${projects.path}${Platform.pathSeparator}$id.backup');
    final zipFile = File('${projects.path}${Platform.pathSeparator}$id.download.zip');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
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
          if (!hasWindowsExecutableHeader(await handle.read(2))) {
            throw const FormatException('ZIP содержит некорректный Windows EXE');
          }
        } finally {
          await handle.close();
        }
      }
      executables.sort((a, b) {
        final aName = a.uri.pathSegments.last.toLowerCase();
        final bName = b.uri.pathSegments.last.toLowerCase();
        final aRank = aName.contains(id.replaceAll('-', '')) ? 0 : 1;
        final bRank = bName.contains(id.replaceAll('-', '')) ? 0 : 1;
        return aRank.compareTo(bRank);
      });
      final relativeExe = executables.first.path.substring(staging.path.length);
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await target.exists()) await target.rename(backup.path);
      try {
        await staging.rename(target.path);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exe_$id', '${target.path}$relativeExe');
        if (await backup.exists()) await backup.delete(recursive: true);
      } catch (_) {
        if (await target.exists()) await target.delete(recursive: true);
        if (await backup.exists()) await backup.rename(target.path);
        rethrow;
      }
    } finally {
      client.close();
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
