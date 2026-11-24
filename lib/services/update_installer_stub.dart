import 'updater.dart';

Future<String> downloadApk(
  UpdateAsset asset, {
  void Function(double? fraction, int loaded)? onProgress,
}) async {
  throw UnsupportedError('Updates can only be installed from the app.');
}

Future<void> installApk(String path) async {
  throw UnsupportedError('Updates can only be installed from the app.');
}
