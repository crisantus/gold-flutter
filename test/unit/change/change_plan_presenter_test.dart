import 'dart:io';

import 'package:gold_flutter/src/change/change_plan.dart';
import 'package:gold_flutter/src/change/change_plan_presenter.dart';
import 'package:gold_flutter/src/prompts/prompt_io.dart';
import 'package:test/test.dart';

void main() {
  final plan = ChangePlan(
    summary: 'Update the project',
    projectRoot: Directory('/work/app'),
    files: const [
      PlannedFileChange(
        relativePath: 'lib/new.dart',
        content: '',
        kind: FileChangeKind.create,
        reason: 'Add the new feature',
      ),
      PlannedFileChange(
        relativePath: 'lib/existing.dart',
        content: '',
        kind: FileChangeKind.modify,
        reason: 'Update the existing feature',
      ),
    ],
    commands: [
      PlannedCommand(
        executable: 'dart',
        arguments: ['format', '.'],
        reason: 'Format generated files',
        mutatesFiles: true,
      ),
    ],
    snapshotRoots: const ['lib', 'test'],
  );

  test('prints populated sections in plan order', () {
    final io = FakePromptIO();

    ChangePlanPresenter(io: io).print(plan);

    expect(io.output, [
      'Update the project',
      'Create',
      '  lib/new.dart — Add the new feature',
      'Modify',
      '  lib/existing.dart — Update the existing feature',
      'Run',
      '  dart format . — Format generated files',
      'Snapshot',
      '  lib',
      '  test',
    ]);
  });

  test('omits empty sections', () {
    final io = FakePromptIO();
    final emptyPlan = ChangePlan(
      summary: 'Nothing to do',
      projectRoot: Directory('/work/app'),
    );

    ChangePlanPresenter(io: io).print(emptyPlan);

    expect(io.output, ['Nothing to do']);
  });

  test('dry run prints files and never consumes confirmation input', () {
    final io = FakePromptIO(['yes']);
    final presenter = ChangePlanPresenter(io: io);
    presenter.print(plan);

    expect(presenter.confirm(assumeYes: false, dryRun: true), isFalse);
    expect(io.output.join('\n'), contains('No files have been changed.'));
    expect(io.prompts, isEmpty);
  });

  test('assume yes confirms without reading input', () {
    final io = FakePromptIO(['no']);

    expect(
      ChangePlanPresenter(io: io).confirm(assumeYes: true, dryRun: false),
      isTrue,
    );
    expect(io.prompts, isEmpty);
  });

  test('interactive confirmation accepts yes, no, and empty', () {
    final yesIo = FakePromptIO(['YES']);
    expect(
      ChangePlanPresenter(io: yesIo).confirm(
        assumeYes: false,
        dryRun: false,
      ),
      isTrue,
    );

    final noIo = FakePromptIO([' no ']);
    expect(
      ChangePlanPresenter(io: noIo).confirm(
        assumeYes: false,
        dryRun: false,
      ),
      isFalse,
    );

    final emptyIo = FakePromptIO(['']);
    expect(
      ChangePlanPresenter(io: emptyIo).confirm(
        assumeYes: false,
        dryRun: false,
      ),
      isTrue,
    );
  });

  test('repeats after unrecognized input', () {
    final io = FakePromptIO(['maybe', 'y']);

    expect(
      ChangePlanPresenter(io: io).confirm(
        assumeYes: false,
        dryRun: false,
      ),
      isTrue,
    );
    expect(io.prompts, hasLength(2));
  });
}

final class FakePromptIO implements PromptIO {
  FakePromptIO([Iterable<String> input = const []]) : _input = input.iterator;

  final Iterator<String> _input;
  final List<String> prompts = [];
  final List<String> output = [];

  @override
  String? readLine() => _input.moveNext() ? _input.current : null;

  @override
  void write(String message) => prompts.add(message);

  @override
  void writeLine(String message) => output.add(message);
}
