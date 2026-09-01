import 'package:gold_flutter/src/docs/documentation_manifest.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips stable hashes and detects user edits', () {
    final manifest = DocumentationManifest(
      version: '0.2.0-dev',
      hashes: {'README.md': DocumentationManifest.sha256Of('generated')},
    );
    final decoded = DocumentationManifest.decode(manifest.encode());

    expect(decoded.version, '0.2.0-dev');
    expect(decoded.canUpdate('README.md', 'generated'), isTrue);
    expect(decoded.canUpdate('README.md', 'user edit'), isFalse);
    expect(decoded.canUpdate('new.md', null), isTrue);
  });
}
