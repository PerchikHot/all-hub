import 'dart:convert';
import 'version_status.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const repository = 'PerchikHot/all-hub';
const _headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'AllHub'};
String get currentPlatform => Platform.isWindows ? 'windows' : Platform.isAndroid ? 'android' : 'other';

class HubProject {
  final String id, name, type, description;
  final String? repo;
  const HubProject({required this.id, required this.name, required this.type, required this.description, this.repo});
  factory HubProject.fromJson(Map<String, dynamic> m) => HubProject(
    id: m['id'].toString(), name: m['name'].toString(),
    type: m['type'].toString(), description: m['description'].toString(),
    repo: m['repo']?.toString());
}

class HubAsset {
  final String name, url, platform, version;
  final bool fromActions;
  final String? releaseNotes;
  const HubAsset(this.name, this.url, this.platform, this.version,
      {this.fromActions = false, this.releaseNotes});
}

class ProjectStatus {
  final String? version, workflow, error, actionsUrl;
  final List<HubAsset> assets;
  const ProjectStatus({this.version, this.workflow, this.error, this.actionsUrl, this.assets = const []});
}

class HubService {
  /// Reject malformed catalogs before caching them. A broken network response
  /// must not replace the last working offline catalog or crash startup.
  static List<HubProject>? parseCatalog(String source) {
    try {
      final decoded = jsonDecode(source);
      // Bound untrusted network catalogs and reject ambiguous project IDs.
      if (decoded is! List || decoded.isEmpty || decoded.length > 100) return null;
      final projects = <HubProject>[];
      final ids = <String>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) return null;
        for (final key in ['id', 'name', 'type', 'description']) {
          final value = item[key];
          if (value is! String || value.trim().isEmpty) return null;
        }
        final id = item['id'] as String;
        if (id != id.trim() ||
            !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*
        projects.add(HubProject.fromJson(item));
      }
      return projects;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Future<List<HubProject>> catalog(String bundled) async {
    final prefs = await SharedPreferences.getInstance();
    var projects = parseCatalog(bundled) ?? <HubProject>[];
    final cached = prefs.getString('catalog_cache');
    final offline = cached == null ? null : parseCatalog(cached);
    if (offline != null) projects = offline;
    try {
      final response = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/$repository/main/assets/projects.json'
      ), headers: _headers).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final remote = parseCatalog(response.body);
        if (remote != null) {
          projects = remote;
          await prefs.setString('catalog_cache', response.body);
        }
      }
    } catch (_) {}
    return projects;
  }

  static String? assetPlatform(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.apk')) return 'android';
    // MSI is not installable by ProjectLauncher yet: never advertise it as
    // a working update. Recognize common portable Windows ZIP labels.
    if (n.endsWith('.exe')) return 'windows';
    // Source archives and debug symbols are not runnable applications, even
    // when their filenames mention Windows. Never offer them for installation.
    if (n.endsWith('.zip') &&
        RegExp(r'(^|[-_.])(source|sources|src|symbols|pdb)([-_.]|$)').hasMatch(n)) {
      return null;
    }
    if (n.endsWith('.zip') &&
        (n.contains('windows') || n.contains('win64') ||
         n.contains('win-x64') || n.contains('win32') ||
         n.contains('win_amd64') || n.contains('desktop'))) {
      return 'windows';
    }
    return null;
  }

  static Future<ProjectStatus> inspect(String repo, {String? projectId}) async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=5'), headers: _headers)
          .timeout(const Duration(seconds: 12)),
        http.get(Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=15'), headers: _headers)
          .timeout(const Duration(seconds: 12)),
      ]);
      final assets = <HubAsset>[];
      String? version, workflow, actionsUrl;
      if (responses[0].statusCode == 200) {
        final releases = jsonDecode(responses[0].body) as List;
        for (final raw in releases) {
          final release = raw as Map<String, dynamic>;
          if (release['draft'] == true || release['prerelease'] == true) continue;
          final tag = (release['tag_name'] ?? 'latest').toString();
          if (!releaseMatchesProject(tag, projectId)) continue;
          final notes = release['body']?.toString().trim();
          final publishedVersion = publishedVersionFromRelease(tag, notes);
          for (final a in (release['assets'] as List? ?? [])) {
            final file = a as Map<String, dynamic>;
            final name = (file['name'] ?? '').toString();
            final platform = assetPlatform(name);
            final url = (file['browser_download_url'] ?? '').toString();
            if (platform != null && url.startsWith('https://')) {
              // A release for another OS must not be shown as an available
              // update on this device without a matching installer.
              if (platform == currentPlatform) version ??= publishedVersion;
              assets.add(HubAsset(name, url, platform, publishedVersion, releaseNotes: notes));
            }
          }
        }
      }
      if (responses[1].statusCode == 200) {
        final runs = (jsonDecode(responses[1].body) as Map<String, dynamic>)['workflow_runs'] as List? ?? [];
        final relevantRuns = runs.cast<Map<String, dynamic>>().where(
          (run) => workflowMatchesProject(
            run['name']?.toString(), projectId, currentPlatform,
          ),
        ).toList();
        if (relevantRuns.isNotEmpty) {
          final run = relevantRuns.first;
          workflow = '${run['status'] ?? 'unknown'} / ${run['conclusion'] ?? 'pending'}';
          // Link the latest relevant run, even if it failed. A previous
          // successful run must not hide the current build failure.
          actionsUrl = run['html_url']?.toString();
        }
      }
      return ProjectStatus(version: version, workflow: workflow, actionsUrl: actionsUrl,
        assets: assets, error: responses[0].statusCode == 403 ? 'GitHub API: ограничение запросов' :
          responses[0].statusCode == 404 ? 'Релизы недоступны или репозиторий закрыт' :
          responses[0].statusCode != 200 ? 'GitHub API: HTTP ${responses[0].statusCode}' : null);
    } catch (e) {
      return ProjectStatus(error: 'Ошибка сети: $e');
    }
  }
}

/// Favorites are local to each installation. The project catalog is shared online.
class HubFavorites {
  static final ValueNotifier<Set<String>> ids = ValueNotifier(<String>{});
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    ids.value = prefs.getStringList('favorites')?.toSet() ?? <String>{};
  }
  static Future<void> toggle(String id) async {
    final next = Set<String>.from(ids.value);
    if (!next.add(id)) next.remove(id);
    ids.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', next.toList());
  }
}
).hasMatch(id) ||
            !ids.add(id)) return null;
        projects.add(HubProject.fromJson(item));
      }
      return projects;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Future<List<HubProject>> catalog(String bundled) async {
    final prefs = await SharedPreferences.getInstance();
    var projects = parseCatalog(bundled) ?? <HubProject>[];
    final cached = prefs.getString('catalog_cache');
    final offline = cached == null ? null : parseCatalog(cached);
    if (offline != null) projects = offline;
    try {
      final response = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/$repository/main/assets/projects.json'
      ), headers: _headers).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final remote = parseCatalog(response.body);
        if (remote != null) {
          projects = remote;
          await prefs.setString('catalog_cache', response.body);
        }
      }
    } catch (_) {}
    return projects;
  }

  static String? assetPlatform(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.apk')) return 'android';
    // MSI is not installable by ProjectLauncher yet: never advertise it as
    // a working update. Recognize common portable Windows ZIP labels.
    if (n.endsWith('.exe')) return 'windows';
    // Source archives and debug symbols are not runnable applications, even
    // when their filenames mention Windows. Never offer them for installation.
    if (n.endsWith('.zip') &&
        RegExp(r'(^|[-_.])(source|sources|src|symbols|pdb)([-_.]|$)').hasMatch(n)) {
      return null;
    }
    if (n.endsWith('.zip') &&
        (n.contains('windows') || n.contains('win64') ||
         n.contains('win-x64') || n.contains('win32') ||
         n.contains('win_amd64') || n.contains('desktop'))) {
      return 'windows';
    }
    return null;
  }

  static Future<ProjectStatus> inspect(String repo, {String? projectId}) async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=5'), headers: _headers)
          .timeout(const Duration(seconds: 12)),
        http.get(Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=15'), headers: _headers)
          .timeout(const Duration(seconds: 12)),
      ]);
      final assets = <HubAsset>[];
      String? version, workflow, actionsUrl;
      if (responses[0].statusCode == 200) {
        final releases = jsonDecode(responses[0].body) as List;
        for (final raw in releases) {
          final release = raw as Map<String, dynamic>;
          if (release['draft'] == true || release['prerelease'] == true) continue;
          final tag = (release['tag_name'] ?? 'latest').toString();
          if (!releaseMatchesProject(tag, projectId)) continue;
          final notes = release['body']?.toString().trim();
          final publishedVersion = publishedVersionFromRelease(tag, notes);
          for (final a in (release['assets'] as List? ?? [])) {
            final file = a as Map<String, dynamic>;
            final name = (file['name'] ?? '').toString();
            final platform = assetPlatform(name);
            final url = (file['browser_download_url'] ?? '').toString();
            if (platform != null && url.startsWith('https://')) {
              // A release for another OS must not be shown as an available
              // update on this device without a matching installer.
              if (platform == currentPlatform) version ??= publishedVersion;
              assets.add(HubAsset(name, url, platform, publishedVersion, releaseNotes: notes));
            }
          }
        }
      }
      if (responses[1].statusCode == 200) {
        final runs = (jsonDecode(responses[1].body) as Map<String, dynamic>)['workflow_runs'] as List? ?? [];
        final relevantRuns = runs.cast<Map<String, dynamic>>().where(
          (run) => workflowMatchesProject(
            run['name']?.toString(), projectId, currentPlatform,
          ),
        ).toList();
        if (relevantRuns.isNotEmpty) {
          final run = relevantRuns.first;
          workflow = '${run['status'] ?? 'unknown'} / ${run['conclusion'] ?? 'pending'}';
          // Link the latest relevant run, even if it failed. A previous
          // successful run must not hide the current build failure.
          actionsUrl = run['html_url']?.toString();
        }
      }
      return ProjectStatus(version: version, workflow: workflow, actionsUrl: actionsUrl,
        assets: assets, error: responses[0].statusCode == 403 ? 'GitHub API: ограничение запросов' :
          responses[0].statusCode == 404 ? 'Релизы недоступны или репозиторий закрыт' :
          responses[0].statusCode != 200 ? 'GitHub API: HTTP ${responses[0].statusCode}' : null);
    } catch (e) {
      return ProjectStatus(error: 'Ошибка сети: $e');
    }
  }
}

/// Favorites are local to each installation. The project catalog is shared online.
class HubFavorites {
  static final ValueNotifier<Set<String>> ids = ValueNotifier(<String>{});
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    ids.value = prefs.getStringList('favorites')?.toSet() ?? <String>{};
  }
  static Future<void> toggle(String id) async {
    final next = Set<String>.from(ids.value);
    if (!next.add(id)) next.remove(id);
    ids.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', next.toList());
  }
}
