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
  final String? sha256Digest;
  const HubAsset(this.name, this.url, this.platform, this.version,
      {this.fromActions = false, this.releaseNotes, this.sha256Digest});
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
    // Avoid parsing unbounded remote or cached JSON into application memory.
    // 100 entries at the allowed field sizes fit well below this limit.
    if (source.length > 256 * 1024) return null;
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
          if (value is! String || value.trim().isEmpty ||
              RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(value)) {
            return null;
          }
        }
        // Limit text from remote catalogs before it reaches UI widgets.
        const maxLengths = <String, int>{
          'id': 64, 'name': 120, 'type': 120, 'description': 1000,
        };
        for (final entry in maxLengths.entries) {
          if ((item[entry.key] as String).length > entry.value) return null;
        }
        // Repositories are GitHub owner/name identifiers, never arbitrary URLs
        // or paths. A null repo is allowed for not-yet-published projects.
        final repo = item['repo'];
        if (repo != null) {
          if (repo is! String || repo.length > 160 ||
              !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo) ||
              repo.split('/').any((part) => part == '.' || part == '..')) {
            return null;
          }
        }
        final id = item['id'] as String;
        if (id != id.trim() ||
            !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id) ||
            !ids.add(id)) {
          return null;
        }
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
    // Release filenames become local downloads: reject path separators,
    // control characters and unusually long names before displaying them.
    if (name.isEmpty || name.length > 200 || name != name.trim() ||
        // Release assets become local filenames; avoid Windows device names
        // and characters with filesystem semantics on either platform.
        RegExp(r'[\\/\x00-\x1f\x7f<>:"|?*]').hasMatch(name) ||
        RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
          caseSensitive: false).hasMatch(name)) {
      return null;
    }
    final n = name.toLowerCase();
    // Reject unsigned or unaligned Android build outputs as updates.
    // Debug APKs remain recognizable for explicitly requested testing.
    if (n.endsWith('.apk')) {
      if (RegExp(r'(^|[-_.])(unsigned|unaligned|androidtest|testonly)([-_.]|$)')
          .hasMatch(n)) {
        return null;
      }
      return 'android';
    }
    // Never offer uninstallers, debugging tools or source archives as
    // Windows installers just because their filenames contain "Windows".
    if ((n.endsWith('.exe') || n.endsWith('.zip')) &&
        RegExp(r'(^|[-_.])(source|sources|src|symbols|pdb|debug|uninstall|uninstaller|crashdump|crashreporter|helper|benchmark|updater)([-_.]|$)')
            .hasMatch(n)) {
      return null;
    }
    // MSI is not installable by ProjectLauncher yet: never advertise it as
    // a working update. Recognize common portable Windows ZIP labels.
    if (n.endsWith('.exe')) return 'windows';
    if (n.endsWith('.zip') &&
        (n.contains('windows') || n.contains('win64') ||
         n.contains('win-x64') || n.contains('win32') ||
         n.contains('win_amd64') || n.contains('desktop'))) {
      return 'windows';
    }
    return null;
  }

  /// GitHub release assets can be in an incomplete upload state. Never
  /// advertise a zero-byte or unfinished package as an installable update.
  static bool isPublishedReleaseAsset(Map<String, dynamic> file) {
    final size = file['size'];
    return file['state'] == 'uploaded' && size is int && size > 0;
  }

  /// Only install packages from the requested repository's GitHub release.
  /// The API response is network data, not an authorization to download
  /// executables from arbitrary domains or another project's release.
  static bool isTrustedReleaseAssetUrl(String repo, String url,
      {String? expectedName, String? expectedTag}) {
    final repositoryParts = repo.split('/');
    final uri = Uri.tryParse(url);
    if (repositoryParts.length != 2 || uri == null ||
        uri.scheme != 'https' || uri.host.toLowerCase() != 'github.com' ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    if (parts.length != 6 ||
        parts[0].toLowerCase() != repositoryParts[0].toLowerCase() ||
        parts[1].toLowerCase() != repositoryParts[1].toLowerCase() ||
        parts[2] != 'releases' || parts[3] != 'download' ||
        (expectedName != null && parts.last != expectedName) ||
        (expectedTag != null && parts[4] != expectedTag) ||
        parts.skip(4).any((part) => part.isEmpty ||
            part == '.' || part == '..' ||
            part.contains('/') || part.contains('\\'))) {
      return false;
    }
    return true;
  }

  /// Report release and Actions failures independently. A healthy release
  /// response does not imply that CI status was fetched successfully.
  static String? apiStatusError(int releaseStatus, int actionsStatus) {
    if (releaseStatus == 403 || releaseStatus == 429) {
      return 'GitHub API: лимит запросов к релизам (HTTP $releaseStatus). Повтори проверку позже';
    }
    if (releaseStatus == 404) return 'Релизы недоступны или репозиторий закрыт';
    if (releaseStatus != 200) return 'GitHub API: HTTP $releaseStatus';
    if (actionsStatus == 403 || actionsStatus == 429) {
      return 'GitHub API: лимит запросов к сборкам (HTTP $actionsStatus). Повтори проверку позже';
    }
    if (actionsStatus != 200) return 'GitHub Actions: HTTP $actionsStatus';
    return null;
  }

  /// GitHub Releases may publish a SHA-256 digest for each binary asset.
  /// Reject malformed supplied digests instead of silently disabling checks.
  static String? parseSha256Digest(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(raw)) {
      return null;
    }
    return raw.substring(7).toLowerCase();
  }

  /// Pick installable assets only from the newest *usable* release per OS.
  /// A previous release may still serve Windows while the newest is Android
  /// only, but never mix older assets into a newer OS version's choices.
  static List<HubAsset> latestPublishedAssets(
      String repo, List<dynamic> releases, String? projectId) {
    final selected = <HubAsset>[];
    final coveredPlatforms = <String>{};
    for (final raw in releases) {
      if (raw is! Map<String, dynamic>) continue;
      final release = raw;
      if (release['draft'] == true || release['prerelease'] == true) continue;
      final tag = (release['tag_name'] ?? '').toString();
      if (projectId != null && !releaseMatchesProject(tag, projectId)) {
        continue;
      }
      final notes = release['body']?.toString().trim();
      final publishedVersion = publishedVersionFromRelease(tag, notes);
      final thisRelease = <HubAsset>[];
      for (final rawAsset in (release['assets'] as List? ?? [])) {
        if (rawAsset is! Map<String, dynamic>) continue;
        if (!isPublishedReleaseAsset(rawAsset)) continue;
        final name = (rawAsset['name'] ?? '').toString();
        final platform = assetPlatform(name);
        final url = (rawAsset['browser_download_url'] ?? '').toString();
        if (platform == null || coveredPlatforms.contains(platform) ||
            !isTrustedReleaseAssetUrl(repo, url,
                expectedName: name, expectedTag: tag)) {
          continue;
        }
        final digest = parseSha256Digest(rawAsset['digest']);
        if (rawAsset['digest'] != null && digest == null) {
          continue;
        }
        thisRelease.add(HubAsset(name, url, platform, publishedVersion,
            releaseNotes: notes, sha256Digest: digest));
      }
      selected.addAll(thisRelease);
      coveredPlatforms.addAll(thisRelease.map((asset) => asset.platform));
      if (coveredPlatforms.contains('android') &&
          coveredPlatforms.contains('windows')) {
        break;
      }
    }
    return selected;
  }

  static Future<ProjectStatus> inspect(String repo, {String? projectId}) async {
    try {
      // Third-party cards need published releases, not private CI metadata.
      // Skipping Actions halves their anonymous GitHub API requests.
      final responses = await Future.wait([
        http.get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=5'), headers: _headers)
          .timeout(const Duration(seconds: 12)),
        if (projectId != null)
          http.get(Uri.parse('https://api.github.com/repos/$repo/actions/runs?per_page=15'), headers: _headers)
            .timeout(const Duration(seconds: 12)),
      ]);
      final assets = <HubAsset>[];
      String? version, workflow, actionsUrl;
      if (responses[0].statusCode == 200) {
        final releases = jsonDecode(responses[0].body) as List;
        assets.addAll(latestPublishedAssets(repo, releases, projectId));
        for (final asset in assets) {
          if (asset.platform == currentPlatform) {
            version = asset.version;
            break;
          }
        }
      }
      if (responses.length > 1 && responses[1].statusCode == 200) {
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
        assets: assets, error: apiStatusError(
          responses[0].statusCode,
          responses.length > 1 ? responses[1].statusCode : 200));
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
