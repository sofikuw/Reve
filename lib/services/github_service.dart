import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/file_item.dart';

/// One device-flow session returned by GitHub.
class DeviceAuthorization {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int intervalSeconds;
  final int expiresInSeconds;

  const DeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.intervalSeconds,
    required this.expiresInSeconds,
  });
}

class GithubService {
  static const String baseUrl = 'https://api.github.com';
  static const Duration _timeout = Duration(seconds: 30);

  /// Android aborts sockets eagerly — when the app is backgrounded (we launch
  /// the browser during device login), when a proxy/VPN resets the TLS
  /// handshake, or on flaky mobile networks — and Dart surfaces that as
  /// `ClientException: Software caused connection abort` (errno 103).
  /// Every call here is safe to repeat, so retry before giving up.
  static const int _attempts = 3;

  static Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    return _withRetry(() => http.get(uri, headers: headers).timeout(_timeout));
  }

  static Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _withRetry(
      () => http.post(uri, headers: headers, body: body).timeout(_timeout),
    );
  }

  static Future<http.Response> _withRetry(
    Future<http.Response> Function() send,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _attempts; attempt++) {
      try {
        return await send();
      } catch (error) {
        if (!_isTransient(error)) rethrow;
        lastError = error;
        if (attempt < _attempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
    throw Exception(networkErrorMessage(lastError));
  }

  static bool _isTransient(Object error) {
    if (error is http.ClientException || error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('software caused connection abort') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('connection terminated') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable');
  }

  /// Human-readable text for a failed network call (no dart:io types, so this
  /// file still compiles for the web build).
  static String networkErrorMessage(Object? error) {
    final text = error?.toString() ?? '';
    final lower = text.toLowerCase();
    if (lower.contains('failed host lookup')) {
      return 'Cannot reach github.com: DNS lookup failed. Check your '
          'connection, VPN or private DNS settings.';
    }
    if (lower.contains('software caused connection abort') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed')) {
      return 'GitHub dropped the connection (the phone aborted the socket). '
          'Retry — if it keeps happening, turn off any VPN/ad-blocker or '
          'keep the app in the foreground while you approve the code.';
    }
    if (error is TimeoutException) {
      return 'github.com did not answer in time. Check your connection.';
    }
    return 'Network request failed: $text';
  }

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'reve-cloud-storage',
      };

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  /// Validates a PAT or OAuth token and returns the matching account.
  static Future<GithubAccount> verifyAndGetUser(String token, String type) async {
    final response = await _get(Uri.parse('$baseUrl/user'), headers: _headers(token));

    if (response.statusCode != 200) {
      throw Exception('GitHub rejected that token (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GithubAccount(
      id: data['id'].toString(),
      username: data['login'] as String,
      name: data['name'] as String?,
      avatarUrl: data['avatar_url'] as String?,
      token: token,
      type: type,
      addedAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // OAuth device flow (no client secret, no backend required)
  // ---------------------------------------------------------------------------

  /// Starts a device-flow session.
  ///
  /// Native builds talk to github.com directly. Flutter web cannot, because
  /// GitHub sends no CORS headers for `/login/device/code`, so pass [backend]
  /// (your reve OAuth broker) and the request is proxied through it instead.
  static Future<DeviceAuthorization> startDeviceFlow(
    String clientId, {
    String scope = 'repo',
    String? backend,
  }) async {
    final base = backend?.trim().replaceAll(RegExp(r'/+$'), '') ?? '';
    final Map<String, dynamic> data;

    if (base.isNotEmpty) {
      final uri = Uri.parse(
        '$base/api/oauth?action=device_start'
        '&client_id=${Uri.encodeComponent(clientId)}'
        '&scope=${Uri.encodeComponent(scope)}',
      );
      final response = await _get(uri);
      data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['error'] != null) {
        throw Exception(
          data['error_description']?.toString() ??
              data['error']?.toString() ??
              'Could not start the device flow (${response.statusCode}).',
        );
      }
    } else {
      final response = await _post(
        Uri.parse('https://github.com/login/device/code'),
        headers: const {'Accept': 'application/json'},
        body: {'client_id': clientId, 'scope': scope},
      );
      data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['error'] != null) {
        throw Exception(
          data['error_description']?.toString() ??
              'Could not start the device flow (${response.statusCode}). '
                  'Is "Device flow" enabled on the OAuth App?',
        );
      }
    }

    return DeviceAuthorization(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      verificationUri:
          (data['verification_uri'] ?? 'https://github.com/login/device') as String,
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// Returns an access token once the user authorized the app.
  /// Returns `null` while GitHub still reports `authorization_pending` or
  /// `slow_down` — the caller should keep polling.
  static Future<String?> pollDeviceFlow(
    String clientId,
    String deviceCode, {
    String? backend,
  }) async {
    final base = backend?.trim().replaceAll(RegExp(r'/+$'), '') ?? '';
    final Map<String, dynamic> data;

    if (base.isNotEmpty) {
      final response = await _post(
        Uri.parse('$base/api/oauth'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': clientId, 'device_code': deviceCode}),
      );
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final response = await _post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: const {'Accept': 'application/json'},
        body: {
          'client_id': clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      data = jsonDecode(response.body) as Map<String, dynamic>;
    }
    final token = data['access_token'] as String?;
    if (token != null && token.isNotEmpty) return token;

    switch (data['error']) {
      case 'authorization_pending':
      case 'slow_down':
        return null;
      case 'expired_token':
        throw Exception('The device code expired. Please restart sign-in.');
      case 'access_denied':
        throw Exception('Authorization was cancelled.');
      default:
        throw Exception(
          data['error_description']?.toString() ?? 'OAuth device flow failed.',
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Repositories & branches
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getRepositories(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member'),
      headers: _headers(token),
    );

    if (response.statusCode != 200) {
      throw Exception('Could not load repositories: ${response.body}');
    }

    final List list = jsonDecode(response.body) as List;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  static Future<Map<String, dynamic>> createRepository(
    String token, {
    required String name,
    String? description,
    bool private = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user/repos'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'description': description,
        'private': private,
        'auto_init': true,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Could not create repository: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<String>> getBranches(String token, String owner, String repo) async {
    final response = await http.get(
      Uri.parse('$baseUrl/repos/$owner/$repo/branches?per_page=100'),
      headers: _headers(token),
    );

    if (response.statusCode != 200) {
      throw Exception('Could not load branches: ${response.body}');
    }

    final List list = jsonDecode(response.body) as List;
    return list.map((e) => e['name'].toString()).toList();
  }

  // ---------------------------------------------------------------------------
  // Contents
  // ---------------------------------------------------------------------------

  static Future<List<GithubFileItem>> getContents(
    String token,
    String owner,
    String repo,
    String path, {
    String? branch,
  }) async {
    final encodedPath = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    var uri = '$baseUrl/repos/$owner/$repo/contents/$encodedPath';
    if (branch != null && branch.isNotEmpty) {
      uri += '?ref=${Uri.encodeComponent(branch)}';
    }

    final response = await http.get(Uri.parse(uri), headers: _headers(token));

    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw Exception('Could not load contents: ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is List) {
      return data.map((e) => GithubFileItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (data is Map) {
      return [GithubFileItem.fromJson(data as Map<String, dynamic>)];
    }
    return [];
  }

  /// Raw bytes of one file, authenticated, whatever its size.
  ///
  /// The Contents API refuses files over 1 MB and public raw URLs 404 on
  /// private repositories, so this walks down: Contents (raw) → Git blobs
  /// (base64, good to 100 MB) → public raw URL.
  static Future<Uint8List> fetchBytes({
    required String token,
    required String owner,
    required String repo,
    required String path,
    String? branch,
    String? sha,
    void Function(double? fraction, int loaded)? onProgress,
  }) async {
    final ref = (branch == null || branch.isEmpty) ? null : branch;
    final contentsUri = '$baseUrl/repos/$owner/$repo/contents/${_encodePath(path)}'
        '${ref == null ? '' : '?ref=${Uri.encodeComponent(ref)}'}';

    final attempts = <_FetchAttempt>[
      if (sha != null && sha.isNotEmpty)
        _FetchAttempt('$baseUrl/repos/$owner/$repo/git/blobs/$sha', auth: true, blob: true),
      _FetchAttempt(contentsUri, auth: true),
      if (ref != null) _FetchAttempt(rawUrl(owner, repo, ref, path), auth: false),
    ];

    final client = http.Client();
    Object? last = 'Could not read $path';
    try {
      for (final attempt in attempts) {
        try {
          final request = http.Request('GET', Uri.parse(attempt.url))
            ..headers.addAll(attempt.auth
                ? {
                    ..._headers(token),
                    'Accept': attempt.blob
                        ? 'application/vnd.github+json'
                        : 'application/vnd.github.raw',
                  }
                : const {'Accept': '*/*', 'User-Agent': 'reve-cloud-storage'});
          final response = await client.send(request).timeout(_timeout);
          if (response.statusCode != 200) {
            await response.stream.drain<void>();
            last = 'GitHub answered ${response.statusCode}';
            continue;
          }
          final bytes = await _readAll(response, onProgress);
          if (!attempt.blob) return bytes;

          final data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
          final content = data is Map ? data['content'] : null;
          if (content is! String) throw const FormatException('Unexpected blob payload');
          return base64Decode(content.replaceAll(RegExp(r'\s'), ''));
        } catch (error) {
          last = error;
        }
      }
    } finally {
      client.close();
    }
    throw Exception(last is String ? last : networkErrorMessage(last));
  }

  static Future<Uint8List> _readAll(
    http.StreamedResponse response,
    void Function(double? fraction, int loaded)? onProgress,
  ) async {
    final total = response.contentLength ?? 0;
    final builder = BytesBuilder(copy: false);
    var loaded = 0;
    await for (final chunk in response.stream) {
      builder.add(chunk);
      loaded += chunk.length;
      onProgress?.call(total > 0 ? loaded / total : null, loaded);
    }
    return builder.takeBytes();
  }

  static String rawUrl(String owner, String repo, String branch, String path) {
    return 'https://raw.githubusercontent.com/$owner/$repo/'
        '${Uri.encodeComponent(branch)}/${_encodePath(path)}';
  }

  static String _encodePath(String path) =>
      path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Uploads one file. The body is written in chunks so [onProgress] can drive
  /// a determinate bar — `http.put` would send it all before the first report.
  static Future<void> uploadFile({
    required String token,
    required String owner,
    required String repo,
    required String path,
    required Uint8List bytes,
    required String message,
    String? branch,
    String? sha,
    void Function(double fraction)? onProgress,
  }) async {
    final body = utf8.encode(jsonEncode({
      'message': message,
      'content': base64Encode(bytes),
      if (branch != null && branch.isNotEmpty) 'branch': branch,
      if (sha != null && sha.isNotEmpty) 'sha': sha,
    }));

    final request = http.StreamedRequest(
      'PUT',
      Uri.parse('$baseUrl/repos/$owner/$repo/contents/${_encodePath(path)}'),
    )
      ..headers.addAll({..._headers(token), 'Content-Type': 'application/json'})
      ..contentLength = body.length;

    final client = http.Client();
    try {
      // Fill the request before sending: a StreamedRequest buffers its sink, so
      // the bar animates per chunk and nothing is left unhandled if `send`
      // fails before we await it.
      const chunkSize = 96 * 1024;
      for (var offset = 0; offset < body.length; offset += chunkSize) {
        final end = offset + chunkSize < body.length ? offset + chunkSize : body.length;
        request.sink.add(body.sublist(offset, end));
        onProgress?.call(end / body.length);
        await Future<void>.delayed(Duration.zero);
      }
      await request.sink.close();

      final response = await client.send(request).timeout(_timeout);
      final text = await response.stream.bytesToString();
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Upload failed: $text');
      }
    } finally {
      client.close();
    }
  }

  static Future<void> deleteFile({
    required String token,
    required String owner,
    required String repo,
    required String path,
    required String sha,
    required String message,
    String? branch,
  }) async {
    final encodedPath = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    final body = {
      'message': message,
      'sha': sha,
      if (branch != null && branch.isNotEmpty) 'branch': branch,
    };

    final response = await http.delete(
      Uri.parse('$baseUrl/repos/$owner/$repo/contents/$encodedPath'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Delete failed: ${response.body}');
    }
  }

  /// Recursively deletes a folder by walking its contents.
  static Future<void> deleteDirectory({
    required String token,
    required String owner,
    required String repo,
    required String path,
    required String message,
    String? branch,
  }) async {
    final children = await getContents(token, owner, repo, path, branch: branch);
    for (final child in children) {
      if (child.isDirectory) {
        await deleteDirectory(
          token: token,
          owner: owner,
          repo: repo,
          path: child.path,
          message: message,
          branch: branch,
        );
      } else {
        await deleteFile(
          token: token,
          owner: owner,
          repo: repo,
          path: child.path,
          sha: child.sha,
          message: message,
          branch: branch,
        );
      }
    }
  }

  /// GitHub has no empty directories, so a folder is a placeholder file.
  static Future<void> createFolder({
    required String token,
    required String owner,
    required String repo,
    required String folderPath,
    required String message,
    String? branch,
  }) async {
    final clean = folderPath.replaceAll(RegExp(r'^/+|/+$'), '');
    final path = '$clean/.gitkeep';
    await uploadFile(
      token: token,
      owner: owner,
      repo: repo,
      path: path,
      bytes: Uint8List.fromList(utf8.encode('reve folder placeholder')),
      message: message,
      branch: branch,
    );
  }
}

class _FetchAttempt {
  final String url;
  final bool auth;
  final bool blob;

  const _FetchAttempt(this.url, {this.auth = false, this.blob = false});
}
