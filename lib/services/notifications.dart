/// Transfer notifications. The browser has no notification channel here.
library;

export 'notifications_stub.dart' if (dart.library.io) 'notifications_io.dart';
