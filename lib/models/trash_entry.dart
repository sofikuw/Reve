/// A deleted item kept just long enough to be restored. Committed files rely
/// on their blob sha; release assets keep the asset id so they are not
/// destroyed until the trash is emptied.
class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.repoId,
    required this.branch,
    required this.deletedAt,
    required this.size,
    required this.message,
    this.isAsset = false,
    this.isDirectory = false,
    this.sha,
    this.assetId,
    this.assetName,
  });

  final String id;
  final String path;
  final String name;
  final int? repoId;
  final String? branch;
  final DateTime deletedAt;
  final int size;
  final String message;
  final bool isAsset;
  final bool isDirectory;
  final String? sha;
  final int? assetId;
  final String? assetName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'repoId': repoId,
        'branch': branch,
        'deletedAt': deletedAt.toIso8601String(),
        'size': size,
        'message': message,
        'isAsset': isAsset,
        'isDirectory': isDirectory,
        'sha': sha,
        'assetId': assetId,
        'assetName': assetName,
      };

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
        id: json['id'] as String,
        path: json['path'] as String,
        name: json['name'] as String,
        repoId: (json['repoId'] as num?)?.toInt(),
        branch: json['branch'] as String?,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        size: (json['size'] as num?)?.toInt() ?? 0,
        message: (json['message'] as String?) ?? '',
        isAsset: json['isAsset'] as bool? ?? false,
        isDirectory: json['isDirectory'] as bool? ?? false,
        sha: json['sha'] as String?,
        assetId: (json['assetId'] as num?)?.toInt(),
        assetName: json['assetName'] as String?,
      );
}
