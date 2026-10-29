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

  test('rejects oversized remote catalogs before caching', () {
    final oversized = List.generate(101, (i) => {
      'id': 'project-$i', 'name': 'Project $i',
      'type': 'app', 'description': 'Test',
    });
    expect(HubService.parseCatalog(jsonEncode(oversized)), isNull);
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
