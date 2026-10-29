import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/hub_service.dart';

void main() {
  test('malformed remote catalogs cannot replace the offline project list', () {
    const valid = '[{"id":"all-hub","name":"All Hub","type":"app","description":"Launcher"},'
        '{"id":"kopilka","name":"Копилка","type":"app","description":"Finance"}]';
    final parsed = HubService.parseCatalog(valid);
    expect(parsed, isNotNull);
    expect(parsed!.map((project) => project.id).toList(), ['all-hub', 'kopilka']);
    for (final invalid in [
      '',
      '<html>not a catalog</html>',
      '[',
      '{}',
      '[]',
      '[null]',
      '[{"id":"all-hub"}]',
      '[{"id":"all-hub","name":" ","type":"app","description":"Launcher"}]',
      '[{"id":"all-hub","name":"All Hub","type":"app","description":"Launcher"},'
          '{"id":"all-hub","name":"Duplicate","type":"app","description":"Duplicate"}]',
      '[{"id":"all-hub ","name":"All Hub","type":"app","description":"Launcher"}]',
      '[{"id":"All-Hub","name":"All Hub","type":"app","description":"Launcher"}]',
      '[{"id":"all--hub","name":"All Hub","type":"app","description":"Launcher"}]',
    ]) {
      expect(HubService.parseCatalog(invalid), isNull, reason: invalid);
    }
  });

  test('rejects unsafe repository identifiers and oversized fields', () {
    Map<String, dynamic> project({Object? repo = 'PerchikHot/all-hub'}) => {
      'id': 'all-hub', 'name': 'All Hub', 'type': 'app',
      'description': 'Launcher', 'repo': repo,
    };
    expect(HubService.parseCatalog(jsonEncode([project()])), isNotNull);
    expect(HubService.parseCatalog(jsonEncode([project(repo: null)])), isNotNull);
    for (final invalidRepo in [
      'https://github.com/PerchikHot/all-hub',
      'PerchikHot/../other',
      'PerchikHot//all-hub',
      '../all-hub',
      'PerchikHot/all-hub?download=1',
      42,
      true,
      '',
    ]) {
      expect(HubService.parseCatalog(jsonEncode([project(repo: invalidRepo)])),
          isNull, reason: '$invalidRepo');
    }
    for (final field in ['id', 'name', 'type', 'description']) {
      final oversized = project()..[field] = List.filled(1100, 'x').join();
      expect(HubService.parseCatalog(jsonEncode([oversized])),
          isNull, reason: field);
    }
  });

  test('rejects oversized remote catalogs before caching', () {
    final oversized = List.generate(101, (i) => {
      'id': 'project-$i', 'name': 'Project $i',
      'type': 'app', 'description': 'Test',
    });
    expect(HubService.parseCatalog(jsonEncode(oversized)), isNull);
  });

  test('oversized and control-character catalogs are rejected', () {
    final normal = jsonEncode([{
      'id': 'all-hub', 'name': 'All Hub', 'type': 'app',
      'description': 'Launcher',
    }]);
    expect(HubService.parseCatalog(normal), isNotNull);
    expect(HubService.parseCatalog(List.filled(256 * 1024 + 1, ' ').join()), isNull);
    for (final invalid in ['Name\u0000Hidden', 'Name\u0007Hidden']) {
      final catalog = jsonEncode([{
        'id': 'all-hub', 'name': invalid, 'type': 'app',
        'description': 'Launcher',
      }]);
      expect(HubService.parseCatalog(catalog), isNull);
    }
  });

  test('Windows portable archives are recognized across common naming schemes', () {
    for (final name in [
      'Kopilka-Windows-portable.zip',
      'Nova-win-x64.zip',
      'ShadowRP-win_amd64.zip',
      'Eclipse-win32.zip',
      'AllHub-win64.zip',
      'desktop-preview.zip',
      'EclipseArena.exe',
    ]) {
      expect(HubService.assetPlatform(name), 'windows', reason: name);
    }
  });

  test('unsupported MSI and source archives are not offered as installers', () {
    for (final name in [
      'setup.msi',
      'windows-source.tar.gz',
      'source.zip',
      'README.md',
      'build.log',
    ]) {
      expect(HubService.assetPlatform(name), isNull, reason: name);
    }
    expect(HubService.assetPlatform('Nova-debug.apk'), 'android');
  });

  test('Windows diagnostic and removal tools are not installable updates', () {
    for (final name in [
      'AllHub-Windows-debug.zip',
      'Nova-Windows-symbols.zip',
      'ShadowRP-uninstall.exe',
      'Kopilka-Windows-crashdump.zip',
      'Eclipse-Windows-pdb.exe',
      'AllHub-Windows-updater.exe',
      'Nova-desktop-helper.exe',
      'ShadowRP-Windows-benchmark.zip',
      'Kopilka-Windows-crashreporter.exe',
    ]) {
      expect(HubService.assetPlatform(name), isNull, reason: name);
    }
    expect(HubService.assetPlatform('AllHub-Windows-portable.zip'), 'windows');
    // Android debug artifacts remain identifiable as APKs for testing.
    expect(HubService.assetPlatform('Nova-debug.apk'), 'android');
  });

  test('release downloads must belong to the inspected GitHub repository', () {
    const repo = 'PerchikHot/all-hub';
    expect(HubService.isTrustedReleaseAssetUrl(repo,
      'https://github.com/PerchikHot/all-hub/releases/download/all-hub-latest/AllHub.apk'), isTrue);
    expect(HubService.isTrustedReleaseAssetUrl(repo,
      'https://github.com/perchikhot/ALL-HUB/releases/download/v1.0.0/AllHub-Windows.zip'), isTrue);
    for (final url in [
      'https://evil.example/PerchikHot/all-hub/releases/download/v1/a.apk',
      'https://github.com/PerchikHot/other/releases/download/v1/a.apk',
      'https://github.com.evil.example/PerchikHot/all-hub/releases/download/v1/a.apk',
      'http://github.com/PerchikHot/all-hub/releases/download/v1/a.apk',
      'https://github.com@evil.example/PerchikHot/all-hub/releases/download/v1/a.apk',
      'https://github.com/PerchikHot/all-hub/archive/main.zip',
      'https://github.com/PerchikHot/all-hub/releases/download/v1/a.apk?redirect=1',
      'https://github.com/PerchikHot/all-hub/releases/download/v1/../a.apk',
    ]) {
      expect(HubService.isTrustedReleaseAssetUrl(repo, url), isFalse, reason: url);
    }
  });

  test('source and symbols ZIPs are not treated as Windows installers', () {
    for (final name in [
      'Nova-Windows-source.zip',
      'all-hub-win-x64-src.zip',
      'ShadowRP-desktop-symbols.zip',
      'windows-pdb.zip',
    ]) {
      expect(HubService.assetPlatform(name), isNull, reason: name);
    }
    expect(HubService.assetPlatform('Nova-Windows-portable.zip'), 'windows');
  });
}
