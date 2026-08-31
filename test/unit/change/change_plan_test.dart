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
    final arguments = ['format', '.'];
    final plan = ChangePlan(
      summary: 'ordered',
      projectRoot: Directory('/work/app'),
      files: const [
        PlannedFileChange(
          relativePath: './lib/first.dart',
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
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: arguments,
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

  test('copies command arguments at construction', () {
    final arguments = ['test'];
    final command = PlannedCommand(
      executable: 'dart',
      arguments: arguments,
      reason: 'verify',
      mutatesFiles: false,
    );

    arguments.add('--reporter expanded');

    expect(command.arguments, ['test']);
  });

  test('preserves immutable coherent text-file preconditions', () {
    final plan = ChangePlan(
      summary: 'guard previewed files',
      projectRoot: Directory('/work/app'),
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'update existing',
          precondition: TextFilePrecondition.exact('before'),
        ),
        PlannedFileChange(
          relativePath: 'lib/new.dart',
          content: 'new',
          kind: FileChangeKind.create,
          reason: 'create new',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
    );

    expect(
      plan.files[0].precondition?.kind,
      TextFilePreconditionKind.exactContent,
    );
    expect(plan.files[0].precondition?.expectedContent, 'before');
    expect(
      plan.files[1].precondition?.kind,
      TextFilePreconditionKind.absent,
    );
    expect(plan.files[1].precondition?.expectedContent, isNull);
  });

  test('rejects text-file preconditions incoherent with the change kind', () {
    for (final change in const [
      PlannedFileChange(
        relativePath: 'lib/create.dart',
        content: 'new',
        kind: FileChangeKind.create,
        reason: 'invalid exact create',
        precondition: TextFilePrecondition.exact('before'),
      ),
      PlannedFileChange(
        relativePath: 'lib/modify.dart',
        content: 'after',
        kind: FileChangeKind.modify,
        reason: 'invalid absent modify',
        precondition: TextFilePrecondition.absent(),
      ),
    ]) {
      expect(
        () => ChangePlan(
          summary: 'invalid precondition',
          projectRoot: Directory('/work/app'),
          files: [change],
        ),
        throwsArgumentError,
      );
    }
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
      commands: [
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

  test('rejects absolute file paths', () {
    expect(
      () => ChangePlan(
        summary: 'absolute file',
        projectRoot: Directory('/work/app'),
        files: const [
          PlannedFileChange(
            relativePath: '/work/app/lib/a.dart',
            content: '',
            kind: FileChangeKind.create,
            reason: 'invalid',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('rejects absolute snapshot roots', () {
    expect(
      () => ChangePlan(
        summary: 'absolute snapshot',
        projectRoot: Directory('/work/app'),
        snapshotRoots: const ['/work/app/lib'],
      ),
      throwsArgumentError,
    );
  });

  test('rejects duplicate snapshot roots after normalization', () {
    expect(
      () => ChangePlan(
        summary: 'duplicate snapshots',
        projectRoot: Directory('/work/app'),
        snapshotRoots: const ['./lib', 'lib/../lib'],
      ),
      throwsArgumentError,
    );
  });

  test('rejects Windows absolute and traversal planned file paths', () {
    for (final unsafePath in const [
      r'C:\outside.dart',
      r'C:outside.dart',
      r'D:/outside.dart',
      r'\\server\share\outside.dart',
      r'\rooted\outside.dart',
      r'lib\..\outside.dart',
      r'lib/..\outside.dart',
    ]) {
      expect(
        () => ChangePlan(
          summary: 'portable file containment',
          projectRoot: Directory('/work/app'),
          files: [
            PlannedFileChange(
              relativePath: unsafePath,
              content: '',
              kind: FileChangeKind.create,
              reason: 'must remain contained',
            ),
          ],
        ),
        throwsArgumentError,
        reason: 'Expected "$unsafePath" to be rejected on every host',
      );
    }
  });

  test('rejects Windows absolute and traversal snapshot roots', () {
    for (final unsafeRoot in const [
      r'C:\generated',
      r'C:generated',
      r'D:/generated',
      r'\\server\share\generated',
      r'\rooted\generated',
      r'lib\..\generated',
      r'lib/..\generated',
    ]) {
      expect(
        () => ChangePlan(
          summary: 'portable snapshot containment',
          projectRoot: Directory('/work/app'),
          snapshotRoots: [unsafeRoot],
        ),
        throwsArgumentError,
        reason: 'Expected "$unsafeRoot" to be rejected on every host',
      );
    }
  });

  test('canonicalizes either separator before duplicate detection', () {
    expect(
      () => ChangePlan(
        summary: 'portable duplicate',
        projectRoot: Directory('/work/app'),
        snapshotRoots: const [r'lib\generated', 'lib/generated'],
      ),
      throwsArgumentError,
    );
  });
}
