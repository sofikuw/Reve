import 'package:flutter_test/flutter_test.dart';
import 'package:reve/providers/reve_provider.dart';

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
}
