class GithubAccount {
  final String id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final String token;
  final String type; // 'pat' or 'oauth'
  final DateTime addedAt;

  GithubAccount({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
    required this.token,
    required this.type,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'avatarUrl': avatarUrl,
        'token': token,
        'type': type,
        'addedAt': addedAt.toIso8601String(),
      };

  factory GithubAccount.fromJson(Map<String, dynamic> json) => GithubAccount(
        id: json['id'].toString(),
        username: json['username'] as String,
        name: json['name'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        token: json['token'] as String,
        type: json['type'] as String? ?? 'pat',
        addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt'] as String) : DateTime.now(),
      );
}
