import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A user-selected PUBLIC GitHub repository. Never accept arbitrary hosts,
/// paths, credentials, URL fragments or private repository API endpoints.
class ExternalRepository {
  final String owner;
  final String name;
  const ExternalRepository(this.owner, this.name);

  String get fullName => '$owner/$name';

  // Length-prefix the owner to avoid slug collisions: a-b/c vs a/b-c.
  String get projectId => 'external-${owner.length}-${owner.toLowerCase()}-${name.toLowerCase()}';

  static ExternalRepository? parse(String input) {
    var value = input.trim();
    if (value.isEmpty || value.length > 180 || value.contains('%') ||
        value.contains('\\') || value.contains('?') || value.contains('#')) {
      return null;
    }
    if (value.contains('://')) {
      // Uri normalizes explicit :443 away. Check the original authority
      // before parsing so only the exact github.com host is accepted.
      if (!RegExp(r'^https://github\.com/', caseSensitive: false)
          .hasMatch(value)) {
        return null;
      }
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' ||
          uri.host.toLowerCase() != 'github.com' ||
          uri.authority.toLowerCase() != 'github.com' ||
          uri.userInfo.isNotEmpty || uri.hasPort || uri.hasQuery || uri.hasFragment) {
        return null;
      }
      value = uri.path;
      if (value.startsWith('/')) {
        value = value.substring(1);
      }
      if (value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
    }
    final parts = value.split('/');
    if (parts.length != 2) {
      return null;
    }
    final owner = parts[0], name = parts[1];
    if (owner.length > 39 || owner.isEmpty ||
        !RegExp(r'^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$').hasMatch(owner) ||
        name.isEmpty || name.length > 100 || name == '.' || name == '..' ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) {
      return null;
    }
    return ExternalRepository(owner, name);
  }
}

class ExternalRepositoryStore {
  static const storageKey = 'allhub_custom_repos_v1';
  static const maxRepositories = 30;

  static Future<List<ExternalRepository>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(storageKey) ?? <String>[];
    final result = <ExternalRepository>[];
    final seen = <String>{};
    for (final raw in entries.take(100)) {
      final repo = ExternalRepository.parse(raw);
      if (repo != null && seen.add(repo.fullName.toLowerCase())) {
        result.add(repo);
        if (result.length == maxRepositories) {
          break;
        }
      }
    }
    return result;
  }

  /// A 404/private/archived repository must not be presented as a verified
  /// public source. This does not guarantee that release binaries are safe.
  static Future<void> verifyPublic(ExternalRepository repo,
      {http.Client? client}) async {
    final ownClient = client ?? http.Client();
    try {
      final response = await ownClient.get(
        Uri.https('api.github.com', '/repos/${repo.fullName}'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'AllHub',
        },
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError(response.statusCode == 404
            ? 'Публичный репозиторий не найден'
            : 'Не удалось проверить репозиторий: HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['private'] != false || decoded['archived'] == true ||
          decoded['disabled'] == true ||
          decoded['full_name'] is! String ||
          (decoded['full_name'] as String).toLowerCase() !=
              repo.fullName.toLowerCase()) {
        throw StateError('Репозиторий не подтверждён как публичный и доступный');
      }
    } finally {
      if (client == null) {
        ownClient.close();
      }
    }
  }

  /// Portable backup contains only public repository identifiers, never
  /// credentials, installed packages, downloaded files or app data.
  static String exportBackup(List<ExternalRepository> repositories) {
    if (repositories.length > maxRepositories) {
      throw StateError('Слишком много репозиториев для резервной копии');
    }
    return jsonEncode({
      'format': 'veyrion-public-repositories',
      'version': 1,
      'repositories': repositories.map((repo) => repo.fullName).toList(),
    });
  }

  /// Fail closed on malformed/oversized backups. Do not silently discard
  /// entries: users must know exactly what would replace their catalog.
  static List<ExternalRepository> parseBackup(String source) {
    if (source.isEmpty || source.length > 8192) {
      throw const FormatException('Неверный размер резервной копии');
    }
    final dynamic decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'veyrion-public-repositories' ||
        decoded['version'] != 1 ||
        decoded['repositories'] is! List) {
      throw const FormatException('Неподдерживаемый формат каталога');
    }
    final raw = decoded['repositories'] as List;
    if (raw.length > maxRepositories) {
      throw const FormatException('Превышен лимит репозиториев');
    }
    final seen = <String>{};
    final result = <ExternalRepository>[];
    for (final value in raw) {
      if (value is! String) {
        throw const FormatException('Неверная запись репозитория');
      }
      final repo = ExternalRepository.parse(value);
      if (repo == null || value != repo.fullName ||
          !seen.add(repo.fullName.toLowerCase())) {
        throw const FormatException('Повторяющийся или неверный репозиторий');
      }
      result.add(repo);
    }
    return result;
  }

  /// Verify every repository before replacing the saved list. Any HTTP error,
  /// private/archived repository or malformed entry leaves the old list intact.
  static Future<int> importBackup(String source, {http.Client? client}) async {
    final repositories = parseBackup(source);
    for (final repo in repositories) {
      await verifyPublic(repo, client: client);
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(storageKey,
        repositories.map((repo) => repo.fullName).toList());
    if (!saved) {
      throw StateError('Не удалось сохранить каталог');
    }
    return repositories.length;
  }

  static Future<bool> add(ExternalRepository repo) async {
    final current = await load();
    if (current.any((item) =>
        item.fullName.toLowerCase() == repo.fullName.toLowerCase())) {
      return false;
    }
    if (current.length >= maxRepositories) {
      throw StateError('Максимум $maxRepositories сторонних репозиториев');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.setStringList(storageKey,
        [...current.map((item) => item.fullName), repo.fullName]);
  }

  static Future<void> remove(ExternalRepository repo) async {
    final current = await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, current
        .where((item) => item.fullName.toLowerCase() !=
            repo.fullName.toLowerCase())
        .map((item) => item.fullName).toList());
  }
}
