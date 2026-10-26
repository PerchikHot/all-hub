import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ProjectLauncher {
  static const _channel = MethodChannel('allhub/launcher');
  static const packages = <String, String>{
    'shadow-rp': 'com.shadowrp.app',
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
        final sink = temporary.openWrite();
        await sink.addStream(response.stream);
        await sink.flush();
        await sink.close();
        if (await temporary.length() < 1024) {
          throw const FormatException('Загруженный EXE слишком мал');
        }
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exe_$id', target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      client.close();
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
