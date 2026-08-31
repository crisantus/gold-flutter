import 'dart:io';

import 'package:gold_flutter/src/generator/staging_area.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('refuses a non-empty destination without changing its files', () async {
    final root = await Directory.systemTemp.createTemp('gold_staging_test_');
    addTearDown(() => root.delete(recursive: true));
    final destination = Directory(p.join(root.path, 'my_app'))..createSync();
    final existing = File(p.join(destination.path, 'keep.txt'))
      ..writeAsStringSync('mine');

    await expectLater(
      StagingArea.create(destination: destination),
      throwsA(isA<DestinationExistsException>()),
    );

    expect(existing.readAsStringSync(), 'mine');
  });

  test('dispose removes only its own unpublished staging directory', () async {
    final root = await Directory.systemTemp.createTemp('gold_staging_test_');
    addTearDown(() => root.delete(recursive: true));
    final unrelated = File(p.join(root.path, 'unrelated.txt'))
      ..writeAsStringSync('keep');
    final staging = await StagingArea.create(
      destination: Directory(p.join(root.path, 'my_app')),
    );

    await staging.dispose();

    expect(unrelated.readAsStringSync(), 'keep');
    expect(staging.directory.existsSync(), isFalse);
  });

  test('publish atomically moves a staged project into place', () async {
    final root = await Directory.systemTemp.createTemp('gold_staging_test_');
    addTearDown(() => root.delete(recursive: true));
    final destination = Directory(p.join(root.path, 'my_app'));
    final staging = await StagingArea.create(destination: destination);
    File(
      p.join(staging.directory.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: my_app');

    await staging.publish();
    await staging.dispose();

    expect(
      File(p.join(destination.path, 'pubspec.yaml')).readAsStringSync(),
      'name: my_app',
    );
    expect(staging.directory.existsSync(), isFalse);
  });
}
