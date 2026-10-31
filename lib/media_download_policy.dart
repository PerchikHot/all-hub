/// Validated media names used by the Android and Windows Downloads/All Hub
/// flow. The response MIME type wins over a misleading URL extension.
String? mediaDownloadFileName(Uri uri, String contentType) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  const mimeExtensions = <String, String>{
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/bmp': '.bmp',
    'video/mp4': '.mp4',
    'video/webm': '.webm',
    'video/quicktime': '.mov',
  };
  final mime = contentType.split(';').first.trim().toLowerCase();
  final rawName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  final sourceExtension = RegExp(
    r'\.(jpg|jpeg|png|gif|webp|bmp|mp4|webm|mov)$',
    caseSensitive: false,
  ).firstMatch(rawName)?.group(0)?.toLowerCase();
  final extension = mimeExtensions[mime] ??
      (mime == 'application/octet-stream' ? sourceExtension : null);
  if (extension == null) return null;
  // Never use a server-controlled path or reserved punctuation as a file name.
  final rawStem = sourceExtension == null
      ? rawName
      : rawName.substring(0, rawName.length - sourceExtension.length);
  final stem = rawStem.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final shortened = stem.length > 80 ? stem.substring(0, 80) : stem;
  return '${shortened.isEmpty ? 'media' : shortened}$extension';
}
