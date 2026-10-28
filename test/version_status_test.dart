import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/version_status.dart';

void main() {
  test('numeric versions compare without lexicographic errors', () {
    expect(comparePublishedVersions('1.9.0', '1.10.0'), lessThan(0));
    expect(comparePublishedVersions('v1.2.3', '1.2.3'), 0);
    expect(comparePublishedVersions('1.2.3+5', '1.2.3+7'), lessThan(0));
    expect(comparePublishedVersions('2.0.0', '1.9.9'), greaterThan(0));
    // A release with an explicit CI build must not be marked current
    // against an installed package that exposes only its semantic version.
    expect(comparePublishedVersions('0.6.0', '0.6.0+42'), isNull);
    expect(comparePublishedVersions('0.6.0+41', '0.6.0'), isNull);
    expect(comparePublishedVersions('0.5.9', '0.6.0+42'), lessThan(0));
    expect(comparePublishedVersions('0.6.1', '0.6.0+42'), greaterThan(0));
  });
  test('explicit release notes provide comparable versions', () {
    expect(publishedVersionFromRelease('shadow-rp-android',
      'Подписанная сборка.\nVersion: 0.18.4'), '0.18.4');
    expect(publishedVersionFromRelease('all-hub-latest',
      'Version: 0.6.0+42'), '0.6.0+42');
    expect(publishedVersionFromRelease('kopilka-latest',
      'version: v1.4.2'), 'v1.4.2');
    expect(publishedVersionFromRelease('all-hub-latest',
      'Изменения:\r\n  Версия: 1.7.2+18\r\nИсправления'), '1.7.2+18');
    expect(publishedVersionFromRelease('nova-android',
      'VERSION: v2.1.0'), 'v2.1.0');
    expect(publishedVersionFromRelease('all-hub-latest',
      'Автоматическая сборка без версии'), 'all-hub-latest');
  });
  test('shared repository release channels never cross-contaminate', () {
    expect(releaseMatchesProject('all-hub-latest', 'all-hub'), isTrue);
    expect(releaseMatchesProject('kopilka-latest', 'kopilka'), isTrue);
    expect(releaseMatchesProject('kopilka-latest', 'all-hub'), isFalse);
    expect(releaseMatchesProject('all-hub-latest', 'kopilka'), isFalse);
    expect(releaseMatchesProject('eclipse-arena-android', 'eclipse-arena'), isTrue);
  });

  test('rolling release tags must not trigger false updates', () {
    expect(comparePublishedVersions('0.18.3', 'shadow-rp-android'), isNull);
    expect(describeUpdateStatus('0.18.3', 'shadow-rp-android'),
      contains('неизвестен'));
    expect(describeUpdateStatus('0.6.0', '0.6.0+42'), contains('номер сборки'));
    expect(describeUpdateStatus('0.6.0+42', '0.6.0'), contains('номер сборки'));
    expect(describeUpdateStatus('0.18.3', null), contains('Нет опубликованного'));
    expect(describeUpdateStatus(null, 'v1.0.0'), contains('неизвестен'));
  });
  test('only newer published versions trigger update notice', () {
    expect(describeUpdateStatus('1.2.0', '1.3.0'), contains('Доступно обновление'));
    expect(describeUpdateStatus('1.3.0', '1.2.0'), contains('новее'));
    expect(describeUpdateStatus('1.3.0', '1.3.0'), contains('актуальная'));
  });
  test('Actions status refers to the matching app and platform', () {
    expect(workflowMatchesProject('Record All Hub Build Status', 'all-hub', 'android'), isFalse);
    expect(workflowMatchesProject('Build All Hub', 'all-hub', 'android'), isTrue);
    expect(workflowMatchesProject('Kopilka standalone APK', 'kopilka', 'android'), isTrue);
    expect(workflowMatchesProject('Build All Hub', 'kopilka', 'android'), isFalse);
    expect(workflowMatchesProject('Kopilka standalone APK', 'kopilka', 'windows'), isFalse);
    expect(workflowMatchesProject('Android debug APK', 'eclipse-arena', 'android'), isTrue);
    expect(workflowMatchesProject('Eclipse Arena Windows EXE', 'eclipse-arena', 'android'), isFalse);
    expect(workflowMatchesProject('Eclipse Arena Windows EXE', 'eclipse-arena', 'windows'), isTrue);
    expect(workflowMatchesProject('Build Android APK', 'shadow-rp', 'android'), isTrue);
    expect(workflowMatchesProject('Build Android APK', 'shadow-rp', 'windows'), isFalse);
    expect(workflowMatchesProject('Android APK', 'nova-game', 'android'), isTrue);
    expect(workflowMatchesProject('Android APK', 'nova-game', 'windows'), isFalse);
    expect(workflowMatchesProject('Build All Hub', 'nova-game', 'android'), isFalse);
    expect(workflowMatchesProject('Build All Hub', 'all-hub', 'linux'), isFalse);
    expect(workflowMatchesProject('Build All Hub', 'unknown-project', 'android'), isFalse);
    expect(workflowMatchesProject('Build Android APK', null, 'android'), isFalse);
  });

  test('install button advertises only confirmed newer versions', () {
    expect(installActionLabel('1.2.0', '1.3.0', 'Скачать APK и установить'),
      'Обновить до 1.3.0');
    expect(installActionLabel('1.3.0', '1.3.0', 'Скачать APK и установить'),
      'Скачать APK и установить');
    expect(installActionLabel('1.3.0', '1.2.0', 'Скачать APK и установить'),
      'Скачать APK и установить');
    expect(installActionLabel(null, '1.3.0', 'Скачать APK и установить'),
      'Скачать APK и установить');
    expect(installActionLabel('1.2.0', 'eclipse-arena-android', 'Скачать APK и установить'),
      'Скачать APK и установить');
  });

}
