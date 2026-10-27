/// A rolling GitHub release tag is not a version. CI may include an
/// explicit published package version in the release description.
String publishedVersionFromRelease(String tag, String? notes) {
  final match = RegExp(r'^Version:\s*(v?\d+\.\d+\.\d+(?:\+\d+)?)\s*
      .firstMatch(notes ?? '');
  return match?.group(1) ?? tag;
}

/// Compare only explicit numeric versions. Moving release tags such as
/// "all-hub-latest" are channels, not version numbers.
int? comparePublishedVersions(String installed, String published) {
  final pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');
  final current = pattern.firstMatch(installed.trim());
  final latest = pattern.firstMatch(published.trim());
  if (current == null || latest == null) return null;
  for (var i = 1; i <= 3; i++) {
    final a = int.parse(current.group(i)!);
    final b = int.parse(latest.group(i)!);
    if (a != b) return a.compareTo(b);
  }
  // Only compare build numbers when both are explicitly available.
  if (current.group(4) != null && latest.group(4) != null) {
    return int.parse(current.group(4)!).compareTo(int.parse(latest.group(4)!));
  }
  return 0;
}

String describeUpdateStatus(String? installed, String? published) {
  if (published == null || published.isEmpty) {
    return 'Нет опубликованного файла для этой платформы';
  }
  if (installed == null || installed.isEmpty) {
    return 'Статус обновления неизвестен: версия установки не определена';
  }
  final comparison = comparePublishedVersions(installed, published);
  if (comparison == null) {
    return 'Статус обновления неизвестен: релиз использует тег без номера версии';
  }
  if (comparison < 0) return 'Доступно обновление: $installed → $published';
  if (comparison > 0) return 'Установленная версия новее опубликованной';
  return 'Установлена актуальная версия';
}
, multiLine: true)
      .firstMatch(notes ?? '');
  return match?.group(1) ?? tag;
}

/// Compare only explicit numeric versions. Moving release tags such as
/// "all-hub-latest" are channels, not version numbers.
int? comparePublishedVersions(String installed, String published) {
  final pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');
  final current = pattern.firstMatch(installed.trim());
  final latest = pattern.firstMatch(published.trim());
  if (current == null || latest == null) return null;
  for (var i = 1; i <= 3; i++) {
    final a = int.parse(current.group(i)!);
    final b = int.parse(latest.group(i)!);
    if (a != b) return a.compareTo(b);
  }
  // Only compare build numbers when both are explicitly available.
  if (current.group(4) != null && latest.group(4) != null) {
    return int.parse(current.group(4)!).compareTo(int.parse(latest.group(4)!));
  }
  return 0;
}

String describeUpdateStatus(String? installed, String? published) {
  if (published == null || published.isEmpty) {
    return 'Нет опубликованного файла для этой платформы';
  }
  if (installed == null || installed.isEmpty) {
    return 'Статус обновления неизвестен: версия установки не определена';
  }
  final comparison = comparePublishedVersions(installed, published);
  if (comparison == null) {
    return 'Статус обновления неизвестен: релиз использует тег без номера версии';
  }
  if (comparison < 0) return 'Доступно обновление: $installed → $published';
  if (comparison > 0) return 'Установленная версия новее опубликованной';
  return 'Установлена актуальная версия';
}
