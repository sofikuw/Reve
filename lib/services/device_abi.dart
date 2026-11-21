/// The phone's CPU ABI, used to pick the right split APK. Web has no ABI.
library;

export 'device_abi_stub.dart' if (dart.library.io) 'device_abi_io.dart';
