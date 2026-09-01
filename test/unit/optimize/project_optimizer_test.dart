import 'dart:io';

import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/optimize/project_optimizer.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:gold_flutter/src/project/project_inspector.dart';
import 'package:test/test.dart';

import '../../support/project_fixture.dart';

void main() {
  test('plans ordered commands and rollback coverage', () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.lock': 'original lock',
      'lib/main.dart': 'void main() {}\n',
      'test/widget_test.dart': '',
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final plan = await const ProjectOptimizer().plan(project);

    expect(
      plan.commands.map(
        (command) => [command.executable, ...command.arguments].join(' '),
      ),
      [
        'flutter pub get',
        'dart format lib test',
        'flutter analyze',
        'flutter test',
      ],
    );
    expect(plan.snapshotRoots, [
      'lib',
      'test',
      'pubspec.yaml',
      'pubspec.lock',
    ]);
  });

  test('stops on failure and restores tool-written source', () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.lock': 'original lock',
      'lib/main.dart': 'original source',
      'test/widget_test.dart': '',
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);
    final executor = _OptimizerExecutor(fixture);
    final optimizer = ProjectOptimizer(
      transaction: ChangeTransaction(executor: executor),
    );

    final report = await optimizer.run(await optimizer.plan(project));

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(executor.calls, [
      'flutter pub get',
      'dart format lib test',
      'flutter analyze',
    ]);
    expect(
        await fixture.file('lib/main.dart').readAsString(), 'original source');
  });
}

final class _OptimizerExecutor implements ProcessExecutor {
  _OptimizerExecutor(this.fixture);

  final ProjectFixture fixture;
  final List<String> calls = [];

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) async {
    final command = [executable, ...arguments].join(' ');
    calls.add(command);
    onStarted?.call();
    if (command == 'dart format lib test') {
      await fixture.write('lib/main.dart', 'formatted source');
    }
    if (command == 'flutter analyze') {
      return const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      );
    }
    return const ProcessOutput(exitCode: 0, stdout: '', stderr: '');
  }
}
