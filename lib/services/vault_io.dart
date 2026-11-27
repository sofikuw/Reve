import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _passphraseKey = 'reve_vault_passphrase';
const _recoveryKey = 'reve_vault_recovery';

Future<bool> hasVaultKey() async =>
    (await _storage.read(key: _passphraseKey)) != null;

Future<void> setVaultPassphrase(String passphrase) async {
  await _storage.write(key: _passphraseKey, value: passphrase.trim());
}

Future<String> vaultRecoveryKey() async {
  final existing = await _storage.read(key: _recoveryKey);
  if (existing != null) return existing;
  final random = Random.secure();
  final key = List<int>.generate(32, (_) => random.nextInt(256));
  final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await _storage.write(key: _recoveryKey, value: hex);
  return hex;
}

Key _key(String passphrase) => Key.fromUtf8(
      passphrase.padRight(32, '0').substring(0, 32),
    );

Future<Uint8List> encryptBytes(Uint8List bytes) async {
  final passphrase = await _storage.read(key: _passphraseKey);
  if (passphrase == null) {
    throw Exception('Set a vault passphrase before encrypting files');
  }
  final encrypter = Encrypter(AES(_key(passphrase)));
  final iv = IV.fromLength(16);
  final encrypted = encrypter.encrypt(base64Encode(bytes), iv: iv);
  return Uint8List.fromList(utf8.encode(encrypted.base64));
}

Future<Uint8List> decryptBytes(Uint8List bytes) async {
  final passphrase = await _storage.read(key: _passphraseKey);
  if (passphrase == null) {
    throw Exception('Set a vault passphrase to open this file');
  }
  final encrypter = Encrypter(AES(_key(passphrase)));
  final iv = IV.fromLength(16);
  final plain = encrypter.decrypt64(utf8.decode(bytes), iv: iv);
  return base64Decode(plain);
}
