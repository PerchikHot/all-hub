/// A rolling GitHub release tag is not a version. CI may include an
/// explicit published package version in the release description.
String publishedVersionFromRelease(String tag, String? notes) {
  final match = RegExp(
    r'^Version:\s*(v?\d+\.\d+\.\d+(?:\+\d+)?)\s*$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(notes ?? '');
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
  // A missing build number cannot prove two same-version packages match.
  // This matters for rolling releases that publish multiple APK builds.
  final currentBuild = current.group(4);
  final latestBuild = latest.group(4);
  if ((currentBuild == null) != (latestBuild == null)) return null;
  if (currentBuild != null && latestBuild != null) {
    return int.parse(currentBuild).compareTo(int.parse(latestBuild));
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
    // Distinguish an unknown release channel from an incomplete build number.
    final numeric = RegExp(r'^v?\d+\.\d+\.\d+(?:\+\d+)?$');
    if (numeric.hasMatch(installed.trim()) && numeric.hasMatch(published.trim())) {
      return 'Статус обновления неизвестен: номер сборки указан только у одной версии';
    }
    return 'Статус обновления неизвестен: релиз использует тег без номера версии';
  }
  if (comparison < 0) return 'Доступно обновление: $installed → $published';
  if (comparison > 0) return 'Установленная версия новее опубликованной';
  return 'Установлена актуальная версия';
}

/// All Hub and Kopilka share one repository but publish separate releases.
/// Never present one application's APK or version as the other's update.
bool releaseMatchesProject(String tag, String? projectId) {
  final normalized = tag.trim().toLowerCase();
  switch (projectId) {
    case 'all-hub':
      return normalized.startsWith('all-hub-');
    case 'kopilka':
      return normalized.startsWith('kopilka-');
    default:
      return true;
  }
}

/// Match Actions runs to the project and platform displayed in All Hub.
/// Status-recording workflows do not build installable packages.
bool workflowMatchesProject(String? workflowName, String? projectId, String platform) {
  final name = workflowName?.trim().toLowerCase() ?? '';
  if (name.isEmpty || name.startsWith('record ')) return false;
  switch (projectId) {
    case 'all-hub':
      return name == 'build all hub' &&
          (platform == 'android' || platform == 'windows');
    case 'kopilka':
      return name.contains('kopilka') && name.contains('apk') && platform == 'android';
    case 'eclipse-arena':
      if (platform == 'android') {
        return name.contains('android') && name.contains('apk');
      }
      if (platform == 'windows') {
        return name.contains('windows') && name.contains('exe');
      }
      return false;
    case 'shadow-rp':
      return platform == 'android' && name.contains('android') && name.contains('apk');
    case 'nova-game':
      // inspect() already scopes runs to PerchikHot/-, not other games.
      return platform == 'android' && name == 'android apk';
    default:
      // An unknown project must not inherit an unrelated workflow status.
      return false;
  }
}

/// Show an explicit update action only when both versions can be compared.
/// Unknown/rolling tags must not be advertised as newer installations.
String installActionLabel(String? installed, String? published, String fallback) {
  if (installed != null && published != null &&
      comparePublishedVersions(installed, published) == -1) {
    return 'Обновить до $published';
  }
  return fallback;
}
