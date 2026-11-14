import 'dart:convert';
import 'dart:io';

/// Installs a socket factory that survives a broken system resolver.
///
/// Every `HttpClient` in the app (including the one `package:http` uses) goes
/// through this: connect by hostname as usual, and only when that fails with a
/// lookup error ask a DNS-over-HTTPS resolver for the address and reconnect.
void installDnsFallback() {
  HttpOverrides.global = _DohHttpOverrides();
}

const Duration _timeout = Duration(seconds: 12);

/// Resolvers are addressed by literal IP so a broken resolver cannot break the
/// lookup that fixes it; both certificates cover the address.
const List<(String, String)> _resolvers = [
  ('https://1.1.1.1/dns-query', 'application/dns-json'),
  ('https://8.8.8.8/resolve', 'application/json'),
];

final Map<String, String> _addresses = {};

class _DohHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..connectionFactory = _connect;
  }
}

Future<ConnectionTask<Socket>> _connect(Uri url, String? proxyHost, int? proxyPort) async {
  Socket socket;
  try {
    socket = await Socket.connect(url.host, url.port, timeout: _timeout);
  } on SocketException catch (error) {
    if (!_isLookupFailure(error)) rethrow;
    final address = await _lookup(url.host);
    if (address == null) rethrow;
    socket = await Socket.connect(address, url.port, timeout: _timeout);
  }
  // The client trusts the factory for the whole connection, TLS included.
  if (url.scheme == 'https') {
    socket = await SecureSocket.secure(socket, host: url.host);
  }
  return ConnectionTask.fromSocket(Future<Socket>.value(socket), () {});
}

bool _isLookupFailure(SocketException error) {
  final text = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  return text.contains('host lookup') ||
      text.contains('no address associated') ||
      text.contains('name or service not known') ||
      text.contains('nodename nor servname');
}

Future<String?> _lookup(String host) async {
  final known = _addresses[host];
  if (known != null) return known;

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 6);
  try {
    for (final resolver in _resolvers) {
      try {
        final uri = Uri.parse('${resolver.$1}?name=${Uri.encodeComponent(host)}&type=A');
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, resolver.$2);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) continue;
        final data = jsonDecode(body);
        final answers = data is Map ? data['Answer'] : null;
        if (answers is! List) continue;
        for (final answer in answers) {
          if (answer is! Map) continue;
          final type = answer['type'];
          final value = answer['data'];
          if ((type == 1 || type == 'A') && value is String && value.contains('.')) {
            _addresses[host] = value;
            return value;
          }
        }
      } catch (_) {
        // Try the next resolver.
      }
    }
  } finally {
    client.close(force: true);
  }
  return null;
}
