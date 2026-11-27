/// Client-side encryption for files stored under the Vault folder.
/// The web build has no secure keystore, so it gets a throwing stub.
library;

export 'vault_stub.dart' if (dart.library.io) 'vault_io.dart';
