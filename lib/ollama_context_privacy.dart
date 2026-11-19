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
