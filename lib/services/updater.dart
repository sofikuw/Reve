import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Which releases the app is willing to install. Beta also accepts alpha,
/// because alpha builds are just the early numbers of a beta cycle.
enum UpdateChannel { stable, beta }

/// An installable APK attached to a release.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;

  String get label => '$name · ${size > 0 ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB' : 'unknown size'}';
}

/// One published release, read from the repository's GitHub releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.channel,
    this.build = 0,
    this.assets = const [],
  });

  final String version;
  final String tag;
  final String title;
  final String notes;
  final String pageUrl;
  final String? channel;
  final int build;
  final List<UpdateAsset> assets;

  /// The APK matching [abi] (for example `arm64-v8a`), or the only APK when
  /// the device ABI is unknown and there is nothing to choose between.
  UpdateAsset? apkFor(String? abi) {
    if (assets.isEmpty) return null;
    if (abi != null && abi.isNotEmpty) {
      for (final asset in assets) {
        if (asset.name.contains(abi)) return asset;
      }
    }
    return assets.length == 1 ? assets.first : null;
  }

  String get label =>
      channel == null ? version : '$version · $channel #${build.toString().padLeft(3, '0')}';

  /// The build installed on this device, so the comparison knows what it is
  /// looking at.
  factory UpdateInfo.installed({String? channel}) => UpdateInfo(
        version: AppConfig.version,
        tag: '',
        title: '',
        notes: '',
        pageUrl: '',
        channel: channel,
        build: AppConfig.build,
      );

  /// Stable outranks beta outranks alpha when the version is the same.
  static int _rank(String? channel) => switch (channel) {
        'alpha' => 0,
        'beta' => 1,
        _ => 2,
      };

  static List<int> _parts(String version) {
    final bits = version.split('.');
    return [
      for (var i = 0; i < 3; i++) int.tryParse(i < bits.length ? bits[i] : '') ?? 0,
    ];
  }

  /// -1, 0 or 1 — [a] versus [b].
  static int compare(UpdateInfo a, UpdateInfo b) {
    final left = _parts(a.version);
    final right = _parts(b.version);
    for (var i = 0; i < 3; i++) {
      if (left[i] != right[i]) return left[i] < right[i] ? -1 : 1;
    }
    final rankA = _rank(a.channel);
    final rankB = _rank(b.channel);
    if (rankA != rankB) return rankA < rankB ? -1 : 1;
    return a.build.compareTo(b.build);
  }

  bool isNewerThan(UpdateInfo other) => compare(this, other) > 0;
}

class Updater {
  const Updater._();

  /// The newest release for [channel], or `null` when there is nothing to
  /// compare against yet. Network and API failures throw.
  static Future<UpdateInfo?> latest({
    required UpdateChannel channel,
    String? token,
  }) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/${AppConfig.updateRepo}/releases?per_page=50'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub answered HTTP ${response.statusCode}');
    }

    UpdateInfo? best;
    for (final release in (jsonDecode(response.body) as List).cast<Map<String, dynamic>>()) {
      if (release['draft'] == true) continue;
      if (channel == UpdateChannel.stable && release['prerelease'] == true) continue;
      final info = fromRelease(release);
      if (info == null) continue;
      if (best == null || info.isNewerThan(best)) best = info;
    }
    return best;
  }

  /// Tags look like `v1.0.0-beta.004`; anything else is ignored rather than
  /// guessed at.
  static UpdateInfo? fromRelease(Map<String, dynamic> release) {
    final tag = (release['tag_name'] as String?)?.trim() ?? '';
    final match = RegExp(r'^v?(\d+\.\d+\.\d+)(?:-(alpha|beta|stable)\.(\d+))?$').firstMatch(tag);
    if (match == null) return null;
    final name = (release['name'] as String?)?.trim() ?? '';
    final assets = <UpdateAsset>[];
    for (final entry in (release['assets'] as List?) ?? const []) {
      if (entry is! Map) continue;
      final assetName = (entry['name'] as String?) ?? '';
      if (!assetName.toLowerCase().endsWith('.apk')) continue;
      final url = entry['browser_download_url'] as String?;
      if (url == null || url.isEmpty) continue;
      assets.add(UpdateAsset(
        name: assetName,
        url: url,
        size: (entry['size'] as num?)?.toInt() ?? 0,
      ));
    }
    return UpdateInfo(
      version: match.group(1)!,
      channel: match.group(2),
      build: int.tryParse(match.group(3) ?? '') ?? 0,
      tag: tag,
      title: name.isEmpty ? tag : name,
      notes: (release['body'] as String?) ?? '',
      pageUrl: (release['html_url'] as String?) ??
          'https://github.com/${AppConfig.updateRepo}/releases',
      assets: assets,
    );
  }
}
