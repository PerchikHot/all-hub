import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/version_status.dart';

void main() {
  test('numeric versions compare without lexicographic errors', () {
    expect(comparePublishedVersions('1.9.0', '1.10.0'), lessThan(0));
    expect(comparePublishedVersions('v1.2.3', '1.2.3'), 0);
    expect(comparePublishedVersions('1.2.3+5', '1.2.3+7'), lessThan(0));
    expect(comparePublishedVersions('2.0.0', '1.9.9'), greaterThan(0));
  });
  test('explicit release notes provide comparable versions', () {
    expect(publishedVersionFromRelease('shadow-rp-android',
      'Подписанная сборка.\nVersion: 0.18.4'), '0.18.4');
    expect(publishedVersionFromRelease('all-hub-latest',
      'Version: 0.6.0+42'), '0.6.0+42');
    expect(publishedVersionFromRelease('all-hub-latest',
      'Автоматическая сборка без версии'), 'all-hub-latest');
  });
  test('rolling release tags must not trigger false updates', () {
    expect(comparePublishedVersions('0.18.3', 'shadow-rp-android'), isNull);
    expect(describeUpdateStatus('0.18.3', 'shadow-rp-android'),
      contains('неизвестен'));
    expect(describeUpdateStatus('0.18.3', null), contains('Нет опубликованного'));
    expect(describeUpdateStatus(null, 'v1.0.0'), contains('неизвестен'));
  });
  test('only newer published versions trigger update notice', () {
    expect(describeUpdateStatus('1.2.0', '1.3.0'), contains('Доступно обновление'));
    expect(describeUpdateStatus('1.3.0', '1.2.0'), contains('новее'));
    expect(describeUpdateStatus('1.3.0', '1.3.0'), contains('актуальная'));
  });
}
