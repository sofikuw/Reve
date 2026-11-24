import 'dart:convert';
import 'dart:io';

/// Installs a socket factory that survives a broken system resolver.
///
/// Every `HttpClient` in the app (including the one `package:http` uses) goes
/// through this: connect by hostname as usual, and only when that fails with a
/// lookup error ask a DNS-over-HTTPS resolver for the address and reconnect.
void installDnsFallback() {
  HttpOverrides.global = _DohHttpOverrides();
  // Warm the host the large-file uploads use. Some phones only fail DNS for
  // uploads.github.com, and a pre-resolved address avoids depending on a
  // lookup working at the exact moment a 45 MB upload starts.
  preResolve('uploads.github.com');
}

const Duration _timeout = Duration(seconds: 12);

/// DoH can return an IP whose route is dead from a particular network (the
/// classic `Connection timed out, host: 20.205.243.161`). These GitHub frontends
/// are reachable over ordinary HTTPS and are used as a last resort.
const List<String> _githubFrontends = [
  '140.82.114.4',
  '140.82.112.3',
  '20.205.243.166',
  '20.27.177.113',
  '57.155.223.240',
];

/// Resolvers addressed by literal IP, with the path each one expects. Several
/// are listed because phones behind a VPN or parental controls often block one
/// of these addresses but not the others.
const List<(String, String, String)> _resolvers = [
  ('1.1.1.1', '/dns-query', 'application/dns-json'),
  ('1.0.0.1', '/dns-query', 'application/dns-json'),
  ('8.8.8.8', '/resolve', 'application/json'),
  ('8.8.4.4', '/resolve', 'application/json'),
];

final Map<String, List<String>> _addresses = {};

/// Resolves [host] in the background so the answer is cached before it is
/// needed. Failures are silent — the normal path still tries the system DNS.
Future<void> preResolve(String host) => _lookup(host);

class _DohHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..connectionFactory = _connect;
  }
}

Future<ConnectionTask<Socket>> _connect(Uri url, String? proxyHost, int? proxyPort) async {
  Socket? socket;
  Object? lastError;
  try {
    socket = await Socket.connect(url.host, url.port, timeout: _timeout);
  } on SocketException catch (error) {
    lastError = error;
  }

  if (socket == null) {
    final resolved = await _lookup(url.host) ?? const <String>[];
    final candidates = <String>[
      ...resolved,
      if (url.host.endsWith('github.com') || url.host.endsWith('githubusercontent.com'))
        ..._githubFrontends,
    ];
    for (final address in candidates) {
      try {
        socket = await Socket.connect(address, url.port, timeout: _timeout);
        lastError = null;
        break;
      } on SocketException catch (error) {
        lastError = error;
        // Do not keep handing out an address that just timed out.
        _addresses[url.host]?.remove(address);
      }
    }
    if (socket == null) throw lastError ?? SocketException('No route to ${url.host}');
  }

  // With a connectionFactory the HttpClient does not do TLS itself: the
  // factory owns the whole connection, handshake included.
  if (url.scheme == 'https') {
    socket = await SecureSocket.secure(socket, host: url.host);
  }
  return ConnectionTask.fromSocket(Future<Socket>.value(socket), () {});
}

Future<List<String>?> _lookup(String host) async {
  final known = _addresses[host];
  if (known != null && known.isNotEmpty) return known;

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 6);
  try {
    for (final resolver in _resolvers) {
      try {
        final uri = Uri.https(resolver.$1, resolver.$2, {
          'name': host,
          'type': 'A',
        });
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, resolver.$3);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) continue;
        final data = jsonDecode(body);
        final answers = data is Map ? data['Answer'] : null;
        if (answers is! List) continue;
        final found = <String>[];
        for (final answer in answers) {
          if (answer is! Map) continue;
          final type = answer['type'];
          final value = answer['data'];
          if ((type == 1 || type == 'A') &&
              value is String &&
              value.contains('.') &&
              !found.contains(value)) {
            found.add(value);
          }
        }
        if (found.isNotEmpty) {
          _addresses[host] = found;
          return found;
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
