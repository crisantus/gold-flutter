import 'dart:io';

import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:gold_flutter/src/project/project_inspector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/fake_process_executor.dart';
import '../../support/project_fixture.dart';

void main() {
  test('walks upward and reads Flutter project metadata', () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.yaml': '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.4.2
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  assets:
    - assets/images/
''',
      'lib/features/example.dart': '',
      'test/widget_test.dart': '',
    });
    addTearDown(fixture.dispose);

    final result = await const ProjectInspector().inspect(
      Directory(p.join(fixture.root.path, 'lib/features')),
    );

    expect(result.root.path, fixture.root.path);
    expect(result.projectName, 'sample_app');
    expect(
        result.dependencies, {'flutter', 'flutter_riverpod', 'flutter_test'});
    expect(result.assets, ['assets/images/']);
    expect(result.hasTests, isTrue);
    expect(result.hasGit, isFalse);
    expect(result.isDirty, isFalse);
  });

  test('rejects a directory outside a Flutter project', () async {
    final root = await Directory.systemTemp.createTemp('gold_not_flutter_');
    addTearDown(() => root.delete(recursive: true));

    expect(
      () => const ProjectInspector().inspect(root),
      throwsA(isA<ProjectInspectionException>()),
    );
  });

  test('continues inspecting a Flutter project when Git status fails',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    await Directory(p.join(fixture.root.path, '.git')).create();
    final executor = FakeProcessExecutor({
      'git status --porcelain': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'not a git repository',
      ),
    });

    final result = await ProjectInspector(executor: executor).inspect(
      fixture.root,
    );

    expect(result.projectName, 'fixture');
    expect(result.hasGit, isFalse);
    expect(result.isDirty, isFalse);
  });
}
