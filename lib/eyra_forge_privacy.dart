/// True when Forge is not on this device, including malformed addresses.
/// A LAN server is remote too: photos and prompts cross the network.
bool forgeRequiresRemoteConsent(String endpoint) {
  final uri = Uri.tryParse(endpoint.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty || uri.userInfo.isNotEmpty) return true;
  final host = uri.host.toLowerCase();
  return host != 'localhost' && host != '127.0.0.1' && host != '::1';
}
