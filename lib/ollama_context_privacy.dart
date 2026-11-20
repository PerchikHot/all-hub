/// Privacy boundary for personal context attached to Ollama requests.
/// LAN, public IPs and hostnames are remote even if the model is self-hosted.
bool isLocalOllamaEndpoint(String endpoint) {
  final uri = Uri.tryParse(endpoint.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  return const {'localhost', '127.0.0.1', '::1'}
      .contains(uri.host.toLowerCase());
}

bool maySendOllamaPersonalContext(String endpoint, {required bool remoteOptIn}) =>
    isLocalOllamaEndpoint(endpoint) || remoteOptIn;

/// A remote-memory grant is valid only for the exact server address the user
/// approved. Switching LAN IP, port, scheme or host must revoke the grant.
/// Old global boolean grants intentionally do not migrate to another server.
bool remoteOllamaContextApproved(String endpoint, String? approvedEndpoint) {
  if (approvedEndpoint == null || approvedEndpoint.trim().isEmpty ||
      isLocalOllamaEndpoint(endpoint)) return false;
  String? normalize(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty || uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) return null;
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), '')).toString();
  }
  final current = normalize(endpoint);
  return current != null && current == normalize(approvedEndpoint);
}
