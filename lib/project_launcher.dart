import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
