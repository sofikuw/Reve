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
    final response = await http.get(Uri.parse('$baseUrl/user'), headers: _headers(token));

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
      final response = await http.get(uri);
      data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['error'] != null) {
        throw Exception(
          data['error_description']?.toString() ??
              data['error']?.toString() ??
              'Could not start the device flow (${response.statusCode}).',
        );
      }
    } else {
      final response = await http.post(
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
      final response = await http.post(
        Uri.parse('$base/api/oauth'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': clientId, 'device_code': deviceCode}),
      );
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final response = await http.post(
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

  static Future<String> getTextFile(
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

    final response = await http.get(
      Uri.parse(uri),
      headers: {..._headers(token), 'Accept': 'application/vnd.github.raw'},
    );

    if (response.statusCode != 200) {
      throw Exception('Could not read file: ${response.body}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  static String rawUrl(String owner, String repo, String branch, String path) {
    final encodedPath = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/$owner/$repo/${Uri.encodeComponent(branch)}/$encodedPath';
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  static Future<void> uploadFile({
    required String token,
    required String owner,
    required String repo,
    required String path,
    required Uint8List bytes,
    required String message,
    String? branch,
    String? sha,
  }) async {
    final encodedPath = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    final body = {
      'message': message,
      'content': base64Encode(bytes),
      if (branch != null && branch.isNotEmpty) 'branch': branch,
      if (sha != null && sha.isNotEmpty) 'sha': sha,
    };

    final response = await http.put(
      Uri.parse('$baseUrl/repos/$owner/$repo/contents/$encodedPath'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Upload failed: ${response.body}');
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
