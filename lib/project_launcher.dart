import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ProjectLauncher {
  static final ValueNotifier<double?> downloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String?> activeDownloadProject = ValueNotifier<String?>(null);
  static Future<void> recordInstalledVersion(String id, String? version) async {
    if (version == null || version.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('installed_version_$id', version);
  }
  static Future<String?> installedVersion(String id) async {
    if (Platform.isAndroid) {
      final packageName = packages[id];
      if (packageName == null) return null;
      try {
        return await _channel.invokeMethod<String>('installedPackageVersion', {'packageName': packageName});
      } catch (_) { return null; }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('installed_version_$id');
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
          if (range == null || !range.startsWith('bytes $existing-')) {
            throw const FormatException('Сервер вернул неверный диапазон APK');
          }
          final slash = range.lastIndexOf('/');
          if (slash != -1) {
            totalLength = int.tryParse(range.substring(slash + 1));
          }
        } else {
          totalLength = response.contentLength;
        }
        final sink = temporary.openWrite(
          mode: isPartial ? FileMode.append : FileMode.write,
        );
        var received = isPartial ? existing : 0;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 45),
          )) {
            sink.add(chunk);
            received += chunk.length;
            if (totalLength != null && totalLength! > 0) {
              downloadProgress.value =
                  (received / totalLength!).clamp(0.0, 1.0);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        final actual = await temporary.length();
        if (totalLength != null && actual < totalLength!) {
          throw const HttpException('Соединение оборвалось до конца APK');
        }
        if (totalLength != null && actual > totalLength!) {
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
  };

  static Future<bool> isAvailable(String id) async {
    if (Platform.isAndroid) {
      final packageName = packages[id];
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
      final packageName = packages[id];
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

  /// Downloads a published APK directly, then asks Android to install it.
  /// Android always requires user confirmation; this cannot silently install apps.
  static Future<void> installAndroidApk(String url, {String? projectId}) async {
    if (!Platform.isAndroid) throw UnsupportedError('Android only');
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com' ||
        !uri.path.toLowerCase().endsWith('.apk')) {
      throw ArgumentError('Нужна прямая ссылка на APK из GitHub Releases');
    }
    activeDownloadProject.value = projectId;
    downloadProgress.value = null;
    final client = http.Client();
    try {
      final cache = await getTemporaryDirectory();
      final apk = File('${cache.path}${Platform.pathSeparator}allhub-install.apk');
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
  static Future<void> installWindowsExe(String id, String url) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'github.com' || !uri.path.toLowerCase().endsWith('.exe')) {
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
        await _download(response, temporary);
        if (await temporary.length() < 1024) {
          throw const FormatException('Загруженный EXE слишком мал');
        }
        final file = await temporary.open();
        try {
          final header = await file.read(2);
          if (header.length != 2 || header[0] != 0x4d || header[1] != 0x5a) {
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
  static Future<void> installWindowsZip(String id, String url) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    if (id.isEmpty || !RegExp(r'^[a-z0-9-]+').hasMatch(id)) {
      throw ArgumentError('Некорректный идентификатор проекта');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com' ||
        !uri.path.toLowerCase().endsWith('.zip')) {
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
      await _download(response, zipFile);
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      final rootPath = staging.absolute.path;
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        if (name.startsWith('/') || name.contains(':') ||
            name.split('/').contains('..')) {
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
      (Platform.isAndroid && packages.containsKey(id));
}
