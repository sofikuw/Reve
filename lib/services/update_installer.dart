/// Downloads and opens an APK. The web build has no filesystem or installer.
library;

export 'update_installer_stub.dart' if (dart.library.io) 'update_installer_io.dart';
