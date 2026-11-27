import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
  static const String uploadsUrl = 'https://uploads.github.com';
  static const Duration _timeout = Duration(seconds: 30);
  /// A whole file body has to finish uploading inside this window.
  static const Duration _uploadTimeout = Duration(minutes: 5);
  /// Release assets are the only path for files the Contents API refuses, and
  /// they can be 2 GB — give a phone on mobile data room to finish.
  static const Duration _assetTimeout = Duration(minutes: 30);

  /// Files over the Contents ceiling live as assets of this release. It is a
  /// prerelease so it never shows up as the repository's "latest release".
  static const String assetTag = 'reve-assets';
  static const String manifestPath = '.reve/assets.json';
  static final Map<String, int> _releaseIds = {};
  static final Map<String, String> _signedUrls = {};
  static final Map<String, DateTime> _signedAt = {};

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
    await for (final chunk in response.stream.timeout(const Duration(minutes: 3))) {
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
  // Release-asset storage (files GitHub's Contents API refuses)
  // ---------------------------------------------------------------------------

  /// The media type stored with the asset, so players and browsers know what
  /// they are streaming instead of seeing `application/octet-stream`.
  static String mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    const types = {
      'mp4': 'video/mp4', 'm4v': 'video/mp4', 'mov': 'video/quicktime',
      'webm': 'video/webm', 'mkv': 'video/x-matroska', 'ogv': 'video/ogg',
      '3gp': 'video/3gpp', 'avi': 'video/x-msvideo', 'mpg': 'video/mpeg',
      'mpeg': 'video/mpeg', 'ts': 'video/mp2t',
      'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'm4b': 'audio/mp4',
      'aac': 'audio/aac', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
      'oga': 'audio/ogg', 'flac': 'audio/flac', 'opus': 'audio/opus',
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'webp': 'image/webp', 'avif': 'image/avif',
      'bmp': 'image/bmp', 'svg': 'image/svg+xml', 'heic': 'image/heic',
      'pdf': 'application/pdf', 'zip': 'application/zip',
      'txt': 'text/plain; charset=utf-8', 'md': 'text/markdown',
      'json': 'application/json',
    };
    return types[ext] ?? 'application/octet-stream';
  }

  /// Asset names are repo-wide inside the release, so keep the original stem
  /// readable and append a salt: two folders can hold `clip.mp4`.
  static String assetFileName(String path) {
    final base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    final ext = dot > 0 ? base.substring(dot).toLowerCase() : '';
    final clean = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final short = clean.length > 60 ? clean.substring(0, 60) : clean;
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(1 << 20).toRadixString(36);
    return '$short-$salt$ext';
  }

  /// Direct download URL for a public repository. Media elements can stream
  /// from it; it redirects to a signed object URL that supports byte ranges.
  static String publicAssetUrl(String owner, String repo, String assetName) =>
      'https://github.com/$owner/$repo/releases/download/$assetTag/'
      '${Uri.encodeComponent(assetName)}';

  /// The release that holds large files — the GitHub "page" for an asset,
  /// since release assets have no node in the repository tree.
  static String assetReleaseUrl(String owner, String repo) =>
      'https://github.com/$owner/$repo/releases/tag/$assetTag';

  /// Every asset currently in the large-file release, newest last. The
  /// committed index says where each one belongs; when it is missing or was
  /// never written, this is what keeps the file visible in the app.
  static Future<List<Map<String, dynamic>>> listReleaseAssets({
    required String token,
    required String owner,
    required String repo,
  }) async {
    final found = await _get(
      Uri.parse('$baseUrl/repos/$owner/$repo/releases/tags/$assetTag'),
      headers: _headers(token),
    );
    if (found.statusCode == 404) return const [];
    if (found.statusCode != 200) {
      throw Exception('Could not read the large-file store (${found.statusCode}).');
    }
    final releaseId =
        (jsonDecode(found.body) as Map<String, dynamic>)['id'] as int;
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= 5; page++) {
      final response = await _get(
        Uri.parse('$baseUrl/repos/$owner/$repo/releases/$releaseId/assets'
            '?per_page=100&page=$page'),
        headers: _headers(token),
      );
      if (response.statusCode != 200) break;
      final page_ = jsonDecode(response.body);
      if (page_ is! List || page_.isEmpty) break;
      for (final entry in page_) {
        if (entry is Map) out.add(Map<String, dynamic>.from(entry));
      }
      if (page_.length < 100) break;
    }
    return out;
  }

  /// `holiday-1a2b3c9x2z1.mp4` → `holiday.mp4`, for assets the index does not
  /// know about. Only strip the salt when it actually looks like one, so a
  /// file genuinely called `my-holiday.mp4` keeps its name.
  static String assetDisplayName(String assetName) {
    final dot = assetName.lastIndexOf('.');
    final stem = dot > 0 ? assetName.substring(0, dot) : assetName;
    final ext = dot > 0 ? assetName.substring(dot) : '';
    final cut = stem.lastIndexOf('-');
    if (cut <= 0) return assetName;
    final salt = stem.substring(cut + 1);
    if (salt.length < 8 || !RegExp(r'^[0-9a-z]+$').hasMatch(salt)) {
      return assetName;
    }
    return '${stem.substring(0, cut)}$ext';
  }

  /// Finds (or creates) the release that holds large files.
  static Future<int> ensureAssetRelease({
    required String token,
    required String owner,
    required String repo,
    String? branch,
  }) async {
    final key = '$owner/$repo';
    final known = _releaseIds[key];
    if (known != null) return known;

    final lookup = await _get(
      Uri.parse('$baseUrl/repos/$owner/$repo/releases/tags/$assetTag'),
      headers: _headers(token),
    );
    if (lookup.statusCode == 200) {
      final id = (jsonDecode(lookup.body) as Map<String, dynamic>)['id'] as int;
      _releaseIds[key] = id;
      return id;
    }
    if (lookup.statusCode != 404) {
      throw Exception('Could not reach the large-file store (${lookup.statusCode}).');
    }

    final created = await _post(
      Uri.parse('$baseUrl/repos/$owner/$repo/releases'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'tag_name': assetTag,
        'name': 'Reve asset storage',
        'body': 'Files too large for a normal commit, uploaded by Reve. '
            'They still show up in the app file manager.',
        'prerelease': true,
        'draft': false,
        if (branch != null && branch.isNotEmpty) 'target_commitish': branch,
      }),
    );
    if (created.statusCode == 409) {
      // Another device created it between the lookup and the POST.
      final again = await _get(
        Uri.parse('$baseUrl/repos/$owner/$repo/releases/tags/$assetTag'),
        headers: _headers(token),
      );
      final id = (jsonDecode(again.body) as Map<String, dynamic>)['id'] as int;
      _releaseIds[key] = id;
      return id;
    }
    if (created.statusCode != 201) {
      throw Exception('Could not create the large-file store: ${created.body}');
    }
    final id = (jsonDecode(created.body) as Map<String, dynamic>)['id'] as int;
    _releaseIds[key] = id;
    return id;
  }

  /// Streams one file into the asset release and returns the asset JSON.
  static Future<Map<String, dynamic>> uploadAsset({
    required String token,
    required String owner,
    required String repo,
    required int releaseId,
    required String name,
    required String mime,
    required int length,
    Uint8List? bytes,
    Stream<List<int>>? source,
    void Function(double fraction)? onProgress,
  }) async {
    // GitHub's asset endpoint refuses chunked bodies ("400 Bad Content-Length"),
    // so a request must always carry the real length. A buffered pick knows it
    // from the byte array; a streamed pick gets it from the file picker.
    final size = bytes != null ? bytes.lengthInBytes : length;
    if (size <= 0) {
      throw Exception('Could not determine this file\'s size, so it was not uploaded.');
    }
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('$uploadsUrl/repos/$owner/$repo/releases/$releaseId/assets'
          '?name=${Uri.encodeComponent(name)}'),
    )
      ..headers.addAll({
        ..._headers(token),
        'Content-Type': mime,
      })
      ..contentLength = size;

    final client = http.Client();
    try {
      final pending = client.send(request).timeout(_assetTimeout);
      var sent = 0;
      try {
        // Same ordering as Contents uploads: start sending first, then feed the
        // body, because closing the sink only completes once the request went out.
        final chunks = source ??
            (bytes == null
                ? const Stream<List<int>>.empty()
                : Stream<List<int>>.fromIterable([bytes]));
        await for (final chunk in chunks) {
          request.sink.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent / size);
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        unawaited(request.sink.close());
      }

      final response = await pending;
      final text = await response.stream.bytesToString().timeout(_timeout);
      if (response.statusCode != 201) {
        throw Exception('Large-file upload failed (${response.statusCode}): $text');
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// Reads `.reve/assets.json` — the list that keeps asset files visible in
  /// the file manager. A missing manifest is an empty one, not an error.
  static Future<AssetManifest> readAssetManifest({
    required String token,
    required String owner,
    required String repo,
    String? branch,
  }) async {
    var uri = '$baseUrl/repos/$owner/$repo/contents/${_encodePath(manifestPath)}';
    if (branch != null && branch.isNotEmpty) {
      uri += '?ref=${Uri.encodeComponent(branch)}';
    }
    final response = await _get(Uri.parse(uri), headers: _headers(token));
    // A fresh repo has no index yet. It must be mutable: the caller writes the
    // first asset into this very map.
    if (response.statusCode == 404) {
      return AssetManifest(<String, Map<String, dynamic>>{}, null);
    }
    if (response.statusCode != 200) {
      throw Exception('Could not read the large-file list (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['content'] as String? ?? '';
    final text = content.isEmpty
        ? ''
        : utf8.decode(
            base64Decode(content.replaceAll(RegExp(r'\s'), '')),
            allowMalformed: true,
          );
    final parsed = text.trim().isEmpty ? null : jsonDecode(text);
    final raw = parsed is Map ? parsed['files'] : null;
    final entries = <String, Map<String, dynamic>>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          entries[entry.key.toString()] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    return AssetManifest(entries, data['sha'] as String?);
  }

  /// Writes the manifest back. Returns the new blob sha; a 409 means another
  /// device wrote first, so the caller re-reads and retries.
  static Future<String?> putAssetManifest({
    required String token,
    required String owner,
    required String repo,
    required Map<String, Map<String, dynamic>> files,
    required String? sha,
    String? branch,
  }) async {
    final body = jsonEncode({
      'message': 'Update large-file index via reve',
      'content': base64Encode(utf8.encode(jsonEncode({'version': 1, 'files': files}))),
      if (sha != null && sha.isNotEmpty) 'sha': sha,
      if (branch != null && branch.isNotEmpty) 'branch': branch,
    });
    final response = await http.put(
      Uri.parse('$baseUrl/repos/$owner/$repo/contents/${_encodePath(manifestPath)}'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: body,
    ).timeout(_timeout);
    if (response.statusCode == 409) throw const ManifestConflict();
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Could not save the large-file list: ${response.body}');
    }
    final data = jsonDecode(response.body);
    return data is Map ? (data['content']?['sha'] as String?) : null;
  }

  static Future<void> deleteAsset({
    required String token,
    required String owner,
    required String repo,
    required int assetId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/repos/$owner/$repo/releases/assets/$assetId'),
      headers: _headers(token),
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('Could not delete the stored file (${response.statusCode}).');
    }
    final key = '$owner/$repo/$assetId';
    _signedUrls.remove(key);
    _signedAt.remove(key);
  }

  /// Turns a private asset into a short-lived signed URL. Players get a plain
  /// URL with no headers, which is what ExoPlayer and AVPlayer handle best.
  static Future<String> signedAssetUrl({
    required String token,
    required String owner,
    required String repo,
    required int assetId,
  }) async {
    final key = '$owner/$repo/$assetId';
    final at = _signedAt[key];
    if (at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 40) &&
        _signedUrls.containsKey(key)) {
      return _signedUrls[key]!;
    }

    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/repos/$owner/$repo/releases/assets/$assetId'),
      )
        ..followRedirects = false
        ..headers.addAll({
          ..._headers(token),
          'Accept': 'application/octet-stream',
        });
      final response = await client.send(request).timeout(_timeout);
      await response.stream.drain<void>();
      final location = response.headers['location'];
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null &&
          location.isNotEmpty) {
        _signedUrls[key] = location;
        _signedAt[key] = DateTime.now();
        return location;
      }
      throw Exception('Could not open the stored file (${response.statusCode}).');
    } finally {
      client.close();
    }
  }

  static Future<Uint8List> fetchAssetBytes({
    required String url,
    void Function(double? fraction, int loaded)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'reve-cloud-storage';
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw Exception('Could not read the stored file (${response.statusCode}).');
      }
      return _readAll(response, onProgress);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Uploads one file. The body is written in chunks while it is being sent so
  /// [onProgress] can drive a determinate bar — `http.put` reports nothing.
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
      // Send first, then feed the body. `sink.close()` only completes once the
      // request has been written, so awaiting it before `send` deadlocks: the
      // bar hits 100% and nothing ever reaches GitHub.
      final pending = client.send(request).timeout(_uploadTimeout);
      const chunkSize = 96 * 1024;
      try {
        for (var offset = 0; offset < body.length; offset += chunkSize) {
          final end =
              offset + chunkSize < body.length ? offset + chunkSize : body.length;
          request.sink.add(body.sublist(offset, end));
          onProgress?.call(end / body.length);
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        unawaited(request.sink.close());
      }

      final response = await pending;
      final text = await response.stream.bytesToString().timeout(_timeout);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Upload failed (${response.statusCode}): $text');
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

  // ---------------------------------------------------------------------------
  // Batched commits + undo-delete (git trees, not the Contents API)
  // ---------------------------------------------------------------------------

  /// All file paths in the branch head's tree — the conflict check for batch
  /// uploads. A repo with no commits yet returns an empty set.
  static Future<Set<String>> committedPaths({
    required String token,
    required String owner,
    required String repo,
    String? branch,
  }) async {
    final ref = await _get(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/ref/heads/${Uri.encodeComponent(branch ?? '')}'),
      headers: _headers(token),
    );
    if (ref.statusCode == 404) return {};
    if (ref.statusCode != 200) {
      throw Exception('Could not read the repository head (${ref.statusCode}).');
    }
    final head =
        (jsonDecode(ref.body) as Map<String, dynamic>)['object']['sha'] as String;
    final commit = await _get(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/commits/$head'),
      headers: _headers(token),
    );
    if (commit.statusCode != 200) {
      throw Exception('Could not read the head commit (${commit.statusCode}).');
    }
    final tree = await _get(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/trees/${(jsonDecode(commit.body) as Map<String, dynamic>)['tree']['sha']}?recursive=true'),
      headers: _headers(token),
    );
    if (tree.statusCode != 200) {
      throw Exception('Could not list the repository tree (${tree.statusCode}).');
    }
    final entries = jsonDecode(tree.body) as Map<String, dynamic>;
    return {
      for (final entry in entries['tree'] as List) entry['path'] as String
    };
  }

  /// Stages raw bytes as a git blob — the batched path skips the base64
  /// Contents bodies (and their 4/3 overhead).
  static Future<String> createBlob({
    required String token,
    required String owner,
    required String repo,
    required List<int> bytes,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/blobs'),
      headers: _headers(token),
      body: jsonEncode({'content': base64Encode(bytes), 'encoding': 'base64'}),
    );
    if (response.statusCode != 201) {
      throw Exception('Could not stage a file (${response.statusCode}).');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['sha'] as String;
  }

  /// Commits [entries] (path → blob sha) as one tree plus one commit and moves
  /// the branch to it. With no commits yet, the new commit has no parent.
  static Future<void> commitTree({
    required String token,
    required String owner,
    required String repo,
    required Map<String, String> entries,
    required String message,
    String? branch,
  }) async {
    final refResponse = await _get(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/ref/heads/${Uri.encodeComponent(branch ?? '')}'),
      headers: _headers(token),
    );
    final head = refResponse.statusCode == 404
        ? null
        : (jsonDecode(refResponse.body) as Map<String, dynamic>)['object']['sha'] as String;

    String? baseTree;
    if (head != null) {
      final commitResponse = await _get(
        Uri.parse('$baseUrl/repos/$owner/$repo/git/commits/$head'),
        headers: _headers(token),
      );
      if (commitResponse.statusCode != 200) {
        throw Exception('Could not read the head commit (${commitResponse.statusCode}).');
      }
      baseTree = (jsonDecode(commitResponse.body) as Map<String, dynamic>)['tree']['sha'] as String;
    }

    final treeResponse = await _post(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/trees'),
      headers: _headers(token),
      body: jsonEncode({
        if (baseTree != null) 'base_tree': baseTree,
        'tree': [
          for (final entry in entries.entries)
            {'path': entry.key, 'mode': '100644', 'type': 'blob', 'sha': entry.value},
        ],
      }),
    );
    if (treeResponse.statusCode != 201) {
      throw Exception('Could not build the file tree (${treeResponse.statusCode}).');
    }
    final treeSha = (jsonDecode(treeResponse.body) as Map<String, dynamic>)['sha'] as String;

    final commitResponse = await _post(
      Uri.parse('$baseUrl/repos/$owner/$repo/git/commits'),
      headers: _headers(token),
      body: jsonEncode({
        'message': message,
        'tree': treeSha,
        if (head != null) 'parents': [head],
      }),
    );
    if (commitResponse.statusCode != 201) {
      throw Exception('Could not create the commit (${commitResponse.statusCode}).');
    }

    if (branch != null && branch.isNotEmpty) {
      final sha = (jsonDecode(commitResponse.body) as Map<String, dynamic>)['sha'] as String;
      final refPatch = await _patch(
        Uri.parse('$baseUrl/repos/$owner/$repo/git/refs/heads/${Uri.encodeComponent(branch)}'),
        headers: _headers(token),
        body: jsonEncode({'sha': sha}),
      );
      if (refPatch.statusCode != 200) {
        throw Exception('Could not move the branch forward (${refPatch.statusCode}).');
      }
    }
  }

  static Future<http.Response> _patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _withRetry(
      () => http.patch(uri, headers: headers, body: body).timeout(_timeout),
    );
  }
}

class _FetchAttempt {
  final String url;
  final bool auth;
  final bool blob;

  const _FetchAttempt(this.url, {this.auth = false, this.blob = false});
}

/// `.reve/assets.json`: logical path → release-asset metadata.
class AssetManifest {
  final Map<String, Map<String, dynamic>> files;
  final String? sha;

  const AssetManifest(this.files, this.sha);

  int get totalBytes => files.values.fold(
        0,
        (sum, file) => sum + ((file['size'] as num?)?.toInt() ?? 0),
      );
}

class ManifestConflict implements Exception {
  const ManifestConflict();
}
