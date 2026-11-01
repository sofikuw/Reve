class GithubFileItem {
  final String name;
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
