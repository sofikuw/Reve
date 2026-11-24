import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

import 'updater.dart';

/// Streams the APK into the app's temp directory. Split APKs are ~20 MB, so
/// this never needs to hold the whole file in memory.
Future<String> downloadApk(
  UpdateAsset asset, {
  void Function(double? fraction, int loaded)? onProgress,
}) async {
  final path = '${Directory.systemTemp.path}/${asset.name}';
  final sink = File(path).openWrite();
  final client = http.Client();
  try {
    final response = await client
        .send(http.Request('GET', Uri.parse(asset.url)))
        .timeout(const Duration(minutes: 10));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw Exception('Download failed (HTTP ${response.statusCode}).');
    }
    final reported = response.contentLength;
    final total = reported != null && reported > 0 ? reported : asset.size;
    var received = 0;
    await for (final chunk in response.stream.timeout(const Duration(minutes: 5))) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(total > 0 ? received / total : null, received);
    }
    return path;
  } finally {
    try {
      await sink.close();
    } catch (_) {
      // The download already failed; the error above says why.
    }
    client.close();
  }
}

/// Hands the APK to Android's package installer. `open_filex` supplies the
/// FileProvider URI that modern Android requires.
Future<void> installApk(String path) async {
  final result = await OpenFilex.open(
    path,
    type: 'application/vnd.android.package-archive',
  );
  if (result.type != ResultType.done) {
    final why = result.message.isEmpty ? 'the installer refused the file' : result.message;
    throw Exception('Installer returned ${result.type.name}: $why. '
        'Allow this app to install unknown apps in Android settings, then try again.');
  }
}
