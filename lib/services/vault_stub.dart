import 'dart:typed_data';

Future<bool> hasVaultKey() async => false;
Future<void> setVaultPassphrase(String passphrase) async {}
Future<String> vaultRecoveryKey() async => '';
Future<Uint8List> encryptBytes(Uint8List bytes) async => bytes;
Future<Uint8List> decryptBytes(Uint8List bytes) async => bytes;
