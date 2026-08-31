import 'dart:io';

import 'package:gold_flutter/src/change/change_plan.dart';
import 'package:test/test.dart';

void main() {
  test('rejects duplicate and escaping paths', () {
    final root = Directory('/work/app');

    expect(
      () => ChangePlan(
        summary: 'unsafe',
        projectRoot: root,
        files: const [
          PlannedFileChange(
            relativePath: '../outside.dart',
            content: '',
            kind: FileChangeKind.create,
            reason: 'invalid',
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => ChangePlan(
        summary: 'duplicate',
        projectRoot: root,
        files: const [
          PlannedFileChange(
            relativePath: 'lib/../lib/a.dart',
            content: 'one',
            kind: FileChangeKind.create,
            reason: 'first',
          ),
          PlannedFileChange(
            relativePath: 'lib/a.dart',
            content: 'two',
            kind: FileChangeKind.modify,
            reason: 'second',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('normalizes paths and preserves operation ordering', () {
    final plan = ChangePlan(
      summary: 'ordered',
      projectRoot: Directory('/work/app'),
      files: const [
        PlannedFileChange(
          relativePath: './lib/../lib/first.dart',
          content: 'first',
          kind: FileChangeKind.create,
          reason: 'first',
        ),
        PlannedFileChange(
          relativePath: 'test/second.dart',
          content: 'second',
          kind: FileChangeKind.modify,
          reason: 'second',
        ),
      ],
      commands: const [
        PlannedCommand(
          executable: 'dart',
          arguments: ['format', '.'],
          reason: 'format',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['./lib', 'test'],
    );

    expect(plan.files.map((file) => file.relativePath), [
      'lib/first.dart',
      'test/second.dart',
    ]);
    expect(plan.snapshotRoots, ['lib', 'test']);
    expect(plan.files[0].kind, FileChangeKind.create);
    expect(plan.files[1].kind, FileChangeKind.modify);
    expect(plan.commands.single.arguments, ['format', '.']);
    expect(plan.commands.single.mutatesFiles, isTrue);
  });

  test('exposes immutable plan collections', () {
    final plan = ChangePlan(
      summary: 'immutable',
      projectRoot: Directory('/work/app'),
      files: const [
        PlannedFileChange(
          relativePath: 'lib/a.dart',
          content: '',
          kind: FileChangeKind.create,
          reason: 'test',
        ),
      ],
      commands: const [
        PlannedCommand(
          executable: 'dart',
          arguments: ['test'],
          reason: 'verify',
          mutatesFiles: false,
        ),
      ],
      snapshotRoots: const ['lib'],
    );

    expect(() => plan.files.clear(), throwsUnsupportedError);
    expect(() => plan.commands.clear(), throwsUnsupportedError);
    expect(() => plan.snapshotRoots.clear(), throwsUnsupportedError);
    expect(
        () => plan.commands.single.arguments.clear(), throwsUnsupportedError);
  });

  test('rejects escaping snapshot roots', () {
    expect(
      () => ChangePlan(
        summary: 'unsafe snapshot',
        projectRoot: Directory('/work/app'),
        snapshotRoots: const ['lib', '../../outside'],
      ),
      throwsArgumentError,
    );
  });
}
