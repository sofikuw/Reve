import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reve/models/file_item.dart';
import 'package:reve/providers/reve_provider.dart';
import 'package:reve/services/github_service.dart';
import 'package:reve/services/updater.dart';

void main() {
  test('categoryFor routes extensions into the auto-sort folders', () {
    expect(ReveProvider.categoryFor('Photo.PNG'), 'images');
    expect(ReveProvider.categoryFor('clip.mp4'), 'media');
    expect(ReveProvider.categoryFor('notes.md'), 'documents');
    expect(ReveProvider.categoryFor('bundle.tar.gz'), 'archives');
    expect(ReveProvider.categoryFor('main.dart'), 'code');
    expect(ReveProvider.categoryFor('LICENSE'), 'others');
  });

  test('upload size guard matches the Contents API budget', () {
    // Measured against the live API: 39 MiB lands, 40 MiB returns 422.
    expect(ReveProvider.maxUploadBytes, 38 * 1024 * 1024);
  });

  test('asset names stay readable, unique and extension-preserving', () {
    final a = GithubService.assetFileName('videos/My clip (final).MP4');
    final b = GithubService.assetFileName('videos/My clip (final).MP4');
    expect(a, endsWith('.mp4'));
    expect(a, startsWith('My_clip__final_'));
    expect(a, isNot(b));
    expect(GithubService.assetFileName('notes'), isNot(contains('.')));
  });

  test('players get a real media type, not octet-stream', () {
    expect(GithubService.mimeFor('clip.MP4'), 'video/mp4');
    expect(GithubService.mimeFor('song.flac'), 'audio/flac');
    expect(GithubService.mimeFor('photo.jpeg'), 'image/jpeg');
    expect(GithubService.mimeFor('archive.7z'), 'application/octet-stream');
  });

  test('asset-backed files keep their path, size and id', () {
    final item = GithubFileItem.fromAsset('videos/clip.mp4', {
      'id': 42,
      'name': 'clip-abc.mp4',
      'size': 123456,
    });
    expect(item.name, 'clip.mp4');
    expect(item.path, 'videos/clip.mp4');
    expect(item.size, 123456);
    expect(item.isAsset, isTrue);
    expect(item.isDirectory, isFalse);
  });

  test('aborted sockets are explained instead of dumped raw', () {
    final aborted = http.ClientException(
      'Software caused connection abort',
      Uri.parse('https://github.com/login/oauth/access_token'),
    );
    final message = GithubService.networkErrorMessage(aborted);
    expect(message, contains('dropped the connection'));
    expect(message, isNot(contains('errno')));
  });

  test('dns failures point at the network settings', () {
    final dns = http.ClientException(
      'Failed host lookup: github.com',
      Uri.parse('https://github.com/login/oauth/access_token'),
    );
    expect(GithubService.networkErrorMessage(dns), contains('DNS'));
  });

  test('release tags are read back into version, channel and build', () {
    final info = Updater.fromRelease({
      'tag_name': 'v1.3.0-beta.004',
      'name': 'reve 1.3.0 · beta #004',
      'html_url': 'https://example.test/r',
      'body': 'notes',
    })!;
    expect(info.version, '1.3.0');
    expect(info.channel, 'beta');
    expect(info.build, 4);
    expect(info.label, '1.3.0 · beta #004');
    expect(Updater.fromRelease({'tag_name': 'nightly'}), isNull);
  });

  test('newer versions and channel ranks win, older builds do not', () {
    UpdateInfo at(String version, String? channel, int build) => UpdateInfo(
          version: version,
          channel: channel,
          build: build,
          tag: '',
          title: '',
          notes: '',
          pageUrl: '',
        );

    final installedBeta = at('1.3.0', 'beta', 2);
    expect(at('1.3.0', 'beta', 3).isNewerThan(installedBeta), isTrue);
    expect(at('1.3.0', 'stable', 1).isNewerThan(installedBeta), isTrue);
    expect(at('1.3.0', 'alpha', 9).isNewerThan(installedBeta), isFalse);
    expect(at('1.2.9', 'stable', 99).isNewerThan(installedBeta), isFalse);
    expect(at('1.4.0', 'alpha', 1).isNewerThan(installedBeta), isTrue);
  });
}
