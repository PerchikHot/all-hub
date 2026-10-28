import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/hub_service.dart';

void main() {
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
}
