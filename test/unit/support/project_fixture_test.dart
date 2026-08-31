import 'package:test/test.dart';

import '../../support/project_fixture.dart';

void main() {
  test('creates a default pubspec and nested files', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/src/main.dart': 'void main() {}'},
    );
    addTearDown(fixture.dispose);

    expect(await fixture.file('pubspec.yaml').readAsString(),
        contains('name: fixture'));
    expect(await fixture.file('lib/src/main.dart').readAsString(),
        'void main() {}');
    expect(
        fixture.file('lib/src/main.dart').path, startsWith(fixture.root.path));
  });

  test('disposes the fixture root recursively', () async {
    final fixture = await ProjectFixture.create(
      files: {'nested/file.txt': 'content'},
    );

    await fixture.dispose();

    expect(await fixture.root.exists(), isFalse);
  });

  test('rejects absolute and escaping paths', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);

    expect(
      () => fixture.file('${fixture.root.path}/absolute.txt'),
      throwsArgumentError,
    );
    expect(() => fixture.file('../outside.txt'), throwsArgumentError);
    await expectLater(
      fixture.write('../outside.txt', 'must not write'),
      throwsArgumentError,
    );
  });
}
