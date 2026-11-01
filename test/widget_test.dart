import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reve/providers/reve_provider.dart';
import 'package:reve/services/github_service.dart';

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
    expect(ReveProvider.maxUploadBytes, 95 * 1024 * 1024);
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
}
