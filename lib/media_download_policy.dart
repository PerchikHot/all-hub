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


/// A CDN may end a response early while still returning HTTP 200.
/// Never publish a truncated GIF/video when Content-Length was supplied.
bool isCompleteMediaDownload(int receivedBytes, int? expectedBytes) {
  if (receivedBytes < 0 || expectedBytes != null && expectedBytes < 0) {
    return false;
  }
  return expectedBytes == null || receivedBytes == expectedBytes;
}

/// Reject HTML error pages and empty/truncated headers masquerading as a
/// successful GIF/video download. Check only a small prefix, never decode
/// entire videos in memory. This is format validation, not a virus scanner.
bool hasMediaFileSignature(String fileName, List<int> prefix) {
  bool at(int offset, List<int> magic) =>
      offset >= 0 && prefix.length >= offset + magic.length &&
      List.generate(magic.length, (i) => prefix[offset + i] == magic[i])
          .every((matches) => matches);
  final extension = fileName.split('.').last.toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return at(0, [0xff, 0xd8, 0xff]);
    case 'png':
      return at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case 'gif':
      return at(0, [71, 73, 70, 56, 55, 97]) ||
          at(0, [71, 73, 70, 56, 57, 97]);
    case 'webp':
      return at(0, [82, 73, 70, 70]) &&
          at(8, [87, 69, 66, 80]);
    case 'bmp':
      return at(0, [66, 77]);
    case 'webm':
      return at(0, [0x1a, 0x45, 0xdf, 0xa3]);
    case 'mp4':
      return at(4, [102, 116, 121, 112]); // ISO BMFF ftyp
    case 'mov':
      return at(4, [102, 116, 121, 112]) ||
          at(4, [109, 111, 111, 118]) || // QuickTime moov
          at(4, [119, 105, 100, 101]); // QuickTime wide
    default:
      return false;
  }
}
