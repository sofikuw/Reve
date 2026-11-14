class GithubFileItem {  final String name;
  final String path;
  final String sha;
  final int size;
  final String type; // 'file' or 'dir'
  final String? downloadUrl;
  final String? htmlUrl;

  GithubFileItem({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.type,
    this.downloadUrl,
    this.htmlUrl,
  });

  bool get isDirectory => type == 'dir';

  factory GithubFileItem.fromJson(Map<String, dynamic> json) => GithubFileItem(
        name: json['name'] as String,
        path: json['path'] as String,
        sha: json['sha'] as String,
        size: json['size'] as int? ?? 0,
        type: json['type'] as String,
        downloadUrl: json['download_url'] as String?,
        htmlUrl: json['html_url'] as String?,
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
