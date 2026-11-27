import 'backup_media.dart';

Future<bool> requestPhotoAccess() async => false;

Future<List<BackupMedia>> recentPhotos({int limit = 20}) async => const [];

Future<Stream<List<int>>?> openBackupMedia(BackupMedia media) async => null;
