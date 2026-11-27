/// Access to the device's camera roll. The web build has no photo library.
library;

export 'photo_backup_stub.dart' if (dart.library.io) 'photo_backup_io.dart';
