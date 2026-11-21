import 'dart:io';

/// Android exposes the ABI through `getprop`; no extra plugin is needed.
Future<String?> deviceAbi() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await Process.run('getprop', ['ro.product.cpu.abi']);
    final abi = (result.stdout as String).trim();
    return abi.isEmpty ? null : abi;
  } catch (_) {
    return null;
  }
}
