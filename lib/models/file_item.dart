class GithubFileItem {
  final String name;
  final String path;
  final String sha;
  final int size;
  final String type; // 'file' or 'dir'
  final String? downloadUrl;
  final String? htmlUrl;

  /// Set for files that live as release assets — too large for a normal
  /// commit. They have no blob sha, so every mutation has to go through the
  /// manifest instead of the Contents API.
  final int? assetId;
  final String? assetName;

  GithubFileItem({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.type,
    this.downloadUrl,
    this.htmlUrl,
    this.assetId,
    this.assetName,
  });

  bool get isDirectory => type == 'dir';
  bool get isAsset => assetId != null;

  factory GithubFileItem.fromJson(Map<String, dynamic> json) => GithubFileItem(
        name: json['name'] as String,
        path: json['path'] as String,
        sha: json['sha'] as String,
        size: json['size'] as int? ?? 0,
        type: json['type'] as String,
        downloadUrl: json['download_url'] as String?,
        htmlUrl: json['html_url'] as String?,
      );

  factory GithubFileItem.fromAsset(String path, Map<String, dynamic> data) =>
      GithubFileItem(
        name: path.split('/').last,
        path: path,
        sha: '',
        size: (data['size'] as num?)?.toInt() ?? 0,
        type: 'file',
        assetId: (data['id'] as num?)?.toInt(),
        assetName: data['name'] as String?,
      );
}

String formatBytes(int size) {
  if (size < 1024) return '$size B';
  const units = ['KB', 'MB', 'GB'];
  var value = size / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value >= 10 ? value.round() : value.toStringAsFixed(1)} ${units[unit]}';
}
