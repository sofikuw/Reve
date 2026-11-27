import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:photo_gallery/photo_gallery.dart';

import 'backup_media.dart';

Future<bool> requestPhotoAccess() async {
  final results = await <Permission>[
    Permission.photos,
    Permission.videos,
    Permission.storage,
  ].request();
  return results.values.any((status) => status.isGranted);
}

/// Newest items from the camera roll, across photos and videos.
Future<List<BackupMedia>> recentPhotos({int limit = 20}) async {
  final out = <BackupMedia>[];
  for (final type in MediumType.values) {
    try {
      final albums = await PhotoGallery.listAlbums(mediumType: type);
      final all = albums.where((album) => album.isAllAlbum).toList();
      if (all.isEmpty) continue;
      final page = await all.first.listMedia(take: limit, lightWeight: true);
      for (final medium in page.items) {
        final isVideo = type == MediumType.video;
        out.add(BackupMedia(
          id: medium.id,
          name: medium.filename ??
              '${medium.id}.${isVideo ? 'mp4' : 'jpg'}',
          size: medium.size ?? 0,
          mime: medium.mimeType ??
              (isVideo ? 'video/mp4' : 'image/jpeg'),
          kind: isVideo ? 'video' : 'image',
        ));
      }
    } catch (_) {
      // Some galleries do not expose an "all" album; the other type still works.
    }
  }
  return out;
}

Future<Stream<List<int>>?> openBackupMedia(BackupMedia media) async {
  try {
    final file = await PhotoGallery.getFile(
      mediumId: media.id,
      mediumType:
          media.kind == 'video' ? MediumType.video : MediumType.image,
      mimeType: media.mime,
    );
    return file.openRead();
  } catch (_) {
    return null;
  }
}
