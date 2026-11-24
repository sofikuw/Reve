import 'dart:io';

/// Android exposes the ABI through `getprop`; read the property file too,
/// because a few phones restrict executing system binaries from apps.
Future<String?> deviceAbi() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await Process.run('getprop', ['ro.product.cpu.abi']);
    final abi = (result.stdout as String).trim();
    if (abi.isNotEmpty) return abi;
  } catch (_) {
    // Fall through to the property file.
  }
  try {
    final props = await File('/system/build.prop').readAsString();
    final match = RegExp(r'^ro\.product\.cpu\.abi=(.+)$', multiLine: true)
        .firstMatch(props);
    if (match != null) return match.group(1)!.trim();
  } catch (_) {
    // No ABI detected: the update dialog offers a chooser.
  }
  return null;
}
