/// One photo or video candidate for automatic backup. Platform-neutral so it
/// can cross the conditional-export boundary.
class BackupMedia {
  const BackupMedia({
    required this.id,
    required this.name,
    required this.size,
    required this.mime,
    required this.kind,
  });

  final String id;
  final String name;
  final int size;
  final String mime;
  final String kind; // 'image' or 'video'
}
