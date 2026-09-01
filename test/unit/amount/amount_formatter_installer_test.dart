import 'dart:io';

import 'package:gold_flutter/src/amount/amount_formatter_answers.dart';
import 'package:gold_flutter/src/amount/amount_formatter_installer.dart';
import 'package:gold_flutter/src/change/change_plan.dart';
import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:gold_flutter/src/project/project_inspector.dart';
import 'package:test/test.dart';

import '../../support/project_fixture.dart';

void main() {
  test('plans dependency, owned files, and focused verification', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final plan = await const AmountFormatterInstaller().plan(
      project,
      AmountFormatterAnswers.defaults(),
    );

    expect(plan.files.map((file) => file.relativePath), [
      'lib/core/utils/money_formatter.dart',
      'test/core/utils/money_formatter_test.dart',
    ]);
    expect(
        plan.files.every((file) => file.kind == FileChangeKind.create), isTrue);
    expect(
      plan.commands.map(
        (command) => [command.executable, ...command.arguments].join(' '),
      ),
      [
        'flutter pub add intl',
        'dart format lib/core/utils/money_formatter.dart '
            'test/core/utils/money_formatter_test.dart',
        'flutter analyze',
        'flutter test test/core/utils/money_formatter_test.dart',
      ],
    );
    expect(plan.snapshotRoots, ['pubspec.yaml', 'pubspec.lock']);
  });

  test('updates owned files and refuses unowned conflicts', () async {
    final ownedFixture = await ProjectFixture.create(files: {
      'lib/core/utils/money_formatter.dart':
          '${AmountFormatterInstaller.ownershipMarker}\nold',
      'test/core/utils/money_formatter_test.dart':
          '${AmountFormatterInstaller.ownershipMarker}\nold',
    });
    addTearDown(ownedFixture.dispose);
    final ownedProject =
        await const ProjectInspector().inspect(ownedFixture.root);
    final ownedPlan = await const AmountFormatterInstaller().plan(
      ownedProject,
      AmountFormatterAnswers.defaults(),
    );
    expect(ownedPlan.files.every((file) => file.kind == FileChangeKind.modify),
        isTrue);

    final conflictFixture = await ProjectFixture.create(files: {
      'lib/core/utils/money_formatter.dart': 'user code',
    });
    addTearDown(conflictFixture.dispose);
    final conflictProject =
        await const ProjectInspector().inspect(conflictFixture.root);
    expect(
      () => const AmountFormatterInstaller().plan(
        conflictProject,
        AmountFormatterAnswers.defaults(),
      ),
      throwsA(isA<AmountFormatterConflictException>()),
    );
  });

  test('restores dependency and generated files after verification failure',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final originalPubspec = await fixture.file('pubspec.yaml').readAsString();
    final project = await const ProjectInspector().inspect(fixture.root);
    final plan = await const AmountFormatterInstaller().plan(
      project,
      AmountFormatterAnswers.defaults(),
    );

    final report = await ChangeTransaction(
      executor: _FailingAmountExecutor(fixture),
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(await fixture.file('pubspec.yaml').readAsString(), originalPubspec);
    expect(await fixture.file('pubspec.lock').exists(), isFalse);
    expect(await fixture.file(AmountFormatterInstaller.sourcePath).exists(),
        isFalse);
    expect(await fixture.file(AmountFormatterInstaller.testPath).exists(),
        isFalse);
  });
}

final class _FailingAmountExecutor implements ProcessExecutor {
  _FailingAmountExecutor(this.fixture);

  final ProjectFixture fixture;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) async {
    onStarted?.call();
    final command = [executable, ...arguments].join(' ');
    if (command == 'flutter pub add intl') {
      await fixture.write('pubspec.yaml', 'mutated');
      await fixture.write('pubspec.lock', 'created lock');
    }
    return ProcessOutput(
      exitCode: command.startsWith('flutter test') ? 1 : 0,
      stdout: '',
      stderr: command.startsWith('flutter test') ? 'failed' : '',
    );
  }
}
