import 'dart:convert';
import 'dart:io';

import 'package:gold_flutter/src/change/change_plan.dart';
import 'package:gold_flutter/src/change/project_file_system.dart';
import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:test/test.dart';

import '../../support/fake_process_executor.dart';
import '../../support/project_fixture.dart';

void main() {
  test('rejects a planned file beneath a project child symlink', () async {
    final fixture = await ProjectFixture.create();
    final outside = await Directory.systemTemp.createTemp('gold_outside_');
    addTearDown(fixture.dispose);
    addTearDown(() => outside.delete(recursive: true));
    await Link(
      fixture.file('linked').path,
    ).create(outside.path, recursive: true);
    final plan = ChangePlan(
      summary: 'symlink escape',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'linked/outside.dart',
          content: 'outside write',
          kind: FileChangeKind.create,
          reason: 'must stay contained',
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(File('${outside.path}/outside.dart').existsSync(), isFalse);
    expect(report.output, contains('symbolic link'));
  });

  test('rejects a snapshot tree containing a symlink before command start',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'generated/keep.txt': 'inside'},
    );
    final outside = await Directory.systemTemp.createTemp('gold_outside_');
    addTearDown(fixture.dispose);
    addTearDown(() => outside.delete(recursive: true));
    final outsideFile = File('${outside.path}/marker.txt');
    await outsideFile.writeAsString('outside before');
    await Link(
      fixture.file('generated/external').path,
    ).create(outside.path);
    var commandStarted = false;
    final executor = _CallbackProcessExecutor((_) async {
      commandStarted = true;
      await outsideFile.writeAsString('outside after');
      return const ProcessOutput(exitCode: 1, stdout: '', stderr: 'failed');
    });
    final plan = ChangePlan(
      summary: 'unsafe snapshot tree',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'generated'],
          reason: 'generate',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['generated'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(commandStarted, isFalse);
    expect(outsideFile.readAsStringSync(), 'outside before');
    expect(report.output, contains('symbolic link'));
  });

  test('does not start a mutating command without rollback coverage', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({'dart format .': 'done'});
    final plan = ChangePlan(
      summary: 'uncovered mutation',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', '.'],
          reason: 'format',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('rollback coverage'));
  });

  test('does not start a mutating command with an escaping path argument',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'dart format ../outside': 'done',
    });
    final plan = ChangePlan(
      summary: 'escaping mutation',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', '../outside'],
          reason: 'unsafe format',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['lib'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('unsafe path argument'));
  });

  test('rejects a dart format target outside its rollback coverage', () async {
    final fixture = await ProjectFixture.create(
      files: {
        'lib/existing.dart': 'old',
        'test/existing_test.dart': 'old test',
      },
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({'dart format test': 'done'});
    final plan = ChangePlan(
      summary: 'unrelated coverage',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'test'],
          reason: 'format tests',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['lib'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('not covered'));
  });

  test('accepts a Windows-style format target covered by an exact planned file',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/file.dart': 'before'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      r'dart format lib\file.dart': 'formatted',
    });
    final plan = ChangePlan(
      summary: 'portable exact coverage',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/file.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'update exact target',
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', r'lib\file.dart'],
          reason: 'format exact target',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isTrue);
    expect(executor.calls, [r'dart format lib\file.dart']);
    expect(fixture.file('lib/file.dart').readAsStringSync(), 'after');
  });

  test('rejects an adjacent Windows-style format target as uncovered',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/file.dart': 'before'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor(const {});
    final plan = ChangePlan(
      summary: 'portable adjacent coverage',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/file.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'update exact target',
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', r'lib\other.dart'],
          reason: 'must not format adjacent target',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('not covered'));
    expect(fixture.file('lib/file.dart').readAsStringSync(), 'before');
  });

  test('rejects traversal before equals in a positional format target',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'dart format ../outside=target.dart': 'done',
    });
    final plan = ChangePlan(
      summary: 'equals traversal',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', '../outside=target.dart'],
          reason: 'unsafe format',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['.'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('unsafe path argument'));
  });

  test('rejects build runner without all source and config coverage', () async {
    final fixture = await ProjectFixture.create(
      files: {
        'lib/source.dart': 'source',
        'test/source_test.dart': 'test source',
      },
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'dart run build_runner build': 'done',
    });
    final plan = ChangePlan(
      summary: 'partial build coverage',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['run', 'build_runner', 'build'],
          reason: 'generate',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['lib'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('test'));
    expect(report.output, contains('pubspec.yaml'));
    expect(report.output, contains('pubspec.lock'));
  });

  test('restores covered build runner roots including an absent lockfile',
      () async {
    final fixture = await ProjectFixture.create(
      files: {
        'lib/source.dart': 'old lib',
        'test/source_test.dart': 'old test',
      },
    );
    addTearDown(fixture.dispose);
    final originalPubspec = fixture.file('pubspec.yaml').readAsStringSync();
    final executor = _CallbackProcessExecutor((_) async {
      await fixture.file('lib/source.dart').writeAsString('new lib');
      await fixture.file('test/source_test.dart').writeAsString('new test');
      await fixture.file('pubspec.yaml').writeAsString('changed pubspec');
      await fixture.file('pubspec.lock').writeAsString('created lock');
      return const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'build failed',
      );
    });
    final plan = ChangePlan(
      summary: 'covered build failure',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['run', 'build_runner', 'build'],
          reason: 'generate',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const [
        'lib',
        'test',
        'pubspec.yaml',
        'pubspec.lock',
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(fixture.file('lib/source.dart').readAsStringSync(), 'old lib');
    expect(
        fixture.file('test/source_test.dart').readAsStringSync(), 'old test');
    expect(fixture.file('pubspec.yaml').readAsStringSync(), originalPubspec);
    expect(fixture.file('pubspec.lock').existsSync(), isFalse);
  });

  test('requires pubspec and lockfile coverage for pub get', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({'flutter pub get': 'done'});
    final plan = ChangePlan(
      summary: 'partial pub coverage',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['pub', 'get'],
          reason: 'resolve packages',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['pubspec.yaml'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('pubspec.lock'));
  });

  test('restores covered pub get files including an absent lockfile', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final originalPubspec = fixture.file('pubspec.yaml').readAsStringSync();
    final executor = _CallbackProcessExecutor((_) async {
      await fixture.file('pubspec.yaml').writeAsString('changed');
      await fixture.file('pubspec.lock').writeAsString('created lock');
      return const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'pub get failed',
      );
    });
    final plan = ChangePlan(
      summary: 'covered pub failure',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['pub', 'get'],
          reason: 'resolve packages',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['pubspec.yaml', 'pubspec.lock'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(fixture.file('pubspec.yaml').readAsStringSync(), originalPubspec);
    expect(fixture.file('pubspec.lock').existsSync(), isFalse);
  });

  test('does not start a mutating shell command', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({'sh -c touch lib/a': ''});
    final plan = ChangePlan(
      summary: 'shell mutation',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'sh',
          arguments: const ['-c', 'touch lib/a'],
          reason: 'unsafe shell',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['lib'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('Unsupported mutating executable'));
  });

  test('rejects known mutations mislabeled as non-mutating before start',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);

    for (final command in [
      PlannedCommand(
        executable: 'dart',
        arguments: const ['format', 'lib'],
        reason: 'format source',
        mutatesFiles: false,
      ),
      PlannedCommand(
        executable: 'dart',
        arguments: const ['run', 'build_runner', 'build'],
        reason: 'generate source',
        mutatesFiles: false,
      ),
      PlannedCommand(
        executable: 'dart',
        arguments: const ['pub', 'get'],
        reason: 'resolve Dart packages',
        mutatesFiles: false,
      ),
      PlannedCommand(
        executable: 'flutter',
        arguments: const ['pub', 'get'],
        reason: 'resolve Flutter packages',
        mutatesFiles: false,
      ),
    ]) {
      final executor = FakeProcessExecutor(const {});
      final plan = ChangePlan(
        summary: 'misclassified mutation',
        projectRoot: fixture.root,
        commands: [command],
      );

      final report = await ChangeTransaction(executor: executor).execute(plan);

      expect(report.success, isFalse);
      expect(executor.calls, isEmpty);
      expect(report.output, contains('marked non-mutating'));
    }
  });

  test('rejects Windows cmd expansion characters before mutation start',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    addTearDown(fixture.dispose);

    for (final unsafeTarget in const [
      r'%TEMP%',
      r'lib/"quoted".dart',
      r'lib/^caret.dart',
      r'lib/!delayed!.dart',
      r'lib/(group).dart',
      r"lib/'single'.dart",
      r'lib/a&b.dart',
      r'lib/a|b.dart',
      r'lib/a<b.dart',
      r'lib/a>b.dart',
    ]) {
      final executor = FakeProcessExecutor(const {});
      final plan = ChangePlan(
        summary: 'unsafe Windows argv',
        projectRoot: fixture.root,
        commands: [
          PlannedCommand(
            executable: 'dart',
            arguments: ['format', unsafeTarget],
            reason: 'format source',
            mutatesFiles: true,
          ),
        ],
        snapshotRoots: const ['lib'],
      );

      final report = await ChangeTransaction(executor: executor).execute(plan);

      expect(report.success, isFalse);
      expect(executor.calls, isEmpty);
      expect(
        report.output,
        contains('unsafe argument'),
        reason: 'Expected "$unsafeTarget" to be rejected before execution',
      );
    }
  });

  test('resolves Windows separators inside the project for transaction writes',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final plan = ChangePlan(
      summary: 'portable write',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: r'lib\nested\created.dart',
          content: 'created',
          kind: FileChangeKind.create,
          reason: 'portable path',
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
    ).execute(plan);

    expect(report.success, isTrue);
    expect(report.created, ['lib/nested/created.dart']);
    expect(
        fixture.file('lib/nested/created.dart').readAsStringSync(), 'created');
    expect(fixture.file(r'lib\nested\created.dart').existsSync(), isFalse);
  });

  test('reports create conflicts and missing modifies as skipped', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'preserve me'},
    );
    addTearDown(fixture.dispose);
    final plan = ChangePlan(
      summary: 'skip conflicts',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'must not overwrite',
          kind: FileChangeKind.create,
          reason: 'conflicting create',
        ),
        PlannedFileChange(
          relativePath: 'lib/missing.dart',
          content: 'must not create',
          kind: FileChangeKind.modify,
          reason: 'missing modify',
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
    ).execute(plan);

    expect(report.success, isTrue);
    expect(report.created, isEmpty);
    expect(report.modified, isEmpty);
    expect(report.skipped, ['lib/existing.dart', 'lib/missing.dart']);
    expect(fixture.file('lib/existing.dart').readAsStringSync(), 'preserve me');
    expect(fixture.file('lib/missing.dart').existsSync(), isFalse);
  });

  test('aborts all writes when an absence precondition no longer holds',
      () async {
    final fixture = await ProjectFixture.create(
      files: {
        'lib/existing.dart': 'before',
        'lib/appeared.dart': 'concurrent content',
      },
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'flutter analyze': 'No issues found',
    });
    final fileSystem = _TrackingSnapshotFileSystem();
    addTearDown(fileSystem.dispose);
    final plan = ChangePlan(
      summary: 'guard an expected create',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'would update',
          precondition: TextFilePrecondition.exact('before'),
        ),
        PlannedFileChange(
          relativePath: 'lib/appeared.dart',
          content: 'generated',
          kind: FileChangeKind.create,
          reason: 'would create',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'must not run',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(report.created, isEmpty);
    expect(report.modified, isEmpty);
    expect(executor.calls, isEmpty);
    expect(fileSystem.snapshotDirectory, isNull);
    expect(report.output, contains('lib/appeared.dart'));
    expect(report.output, contains('expected file to be absent'));
    expect(fixture.file('lib/existing.dart').readAsStringSync(), 'before');
    expect(
      fixture.file('lib/appeared.dart').readAsStringSync(),
      'concurrent content',
    );
  });

  test('aborts before commands when exact original content has changed',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'changed concurrently'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'flutter analyze': 'No issues found',
    });
    final plan = ChangePlan(
      summary: 'guard an expected modify',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'would update',
          precondition: TextFilePrecondition.exact('previewed content'),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'must not run',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/existing.dart'));
    expect(report.output, contains('original content changed'));
    expect(
      fixture.file('lib/existing.dart').readAsStringSync(),
      'changed concurrently',
    );
  });

  test('aborts before commands when an exact-content file disappeared',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'flutter analyze': 'No issues found',
    });
    final plan = ChangePlan(
      summary: 'guard a removed modify',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/missing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'would update',
          precondition: TextFilePrecondition.exact('previewed content'),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'must not run',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/missing.dart'));
    expect(report.output, contains('file is missing'));
    expect(fixture.file('lib/missing.dart').existsSync(), isFalse);
  });

  test('applies guarded changes when every precondition still holds', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'before'},
    );
    addTearDown(fixture.dispose);
    final plan = ChangePlan(
      summary: 'apply guarded files',
      projectRoot: fixture.root,
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

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
    ).execute(plan);

    expect(report.success, isTrue);
    expect(report.modified, ['lib/existing.dart']);
    expect(report.created, ['lib/new.dart']);
    expect(fixture.file('lib/existing.dart').readAsStringSync(), 'after');
    expect(fixture.file('lib/new.dart').readAsStringSync(), 'new');
  });

  test('matches an unchanged UTF-8 BOM file using decoded text semantics',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final file = fixture.file('lib/existing.dart');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([..._utf8Bom, ...utf8.encode('before')]);
    final previewed = await file.readAsString();
    expect(previewed, 'before');
    final plan = ChangePlan(
      summary: 'guard BOM text',
      projectRoot: fixture.root,
      files: [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'update existing',
          precondition: TextFilePrecondition.exact(previewed),
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
    ).execute(plan);

    expect(report.success, isTrue);
    expect(report.modified, ['lib/existing.dart']);
    expect(file.readAsStringSync(), 'after');
  });

  test('rejects a genuine text change in a UTF-8 BOM file', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final file = fixture.file('lib/existing.dart');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([..._utf8Bom, ...utf8.encode('before')]);
    final previewed = await file.readAsString();
    final plan = ChangePlan(
      summary: 'guard changed BOM text',
      projectRoot: fixture.root,
      files: [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'would update',
          precondition: TextFilePrecondition.exact(previewed),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'must not run',
          mutatesFiles: false,
        ),
      ],
    );
    await file.writeAsBytes([..._utf8Bom, ...utf8.encode('changed')]);
    final executor = FakeProcessExecutor.success({
      'flutter analyze': 'No issues found',
    });

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/existing.dart'));
    expect(report.output, contains('original content changed'));
    expect(file.readAsStringSync(), 'changed');
  });

  test('fails a text precondition closed for invalid UTF-8 bytes', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final file = fixture.file('lib/existing.dart');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [0xff, 0xfe, 0xfd]);
    final executor = FakeProcessExecutor.success({
      'flutter analyze': 'No issues found',
    });
    final plan = ChangePlan(
      summary: 'guard invalid text',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'after',
          kind: FileChangeKind.modify,
          reason: 'must not update',
          precondition: TextFilePrecondition.exact('previewed'),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'must not run',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/existing.dart'));
    expect(report.output, contains('invalid UTF-8'));
    expect(await file.readAsBytes(), const [0xff, 0xfe, 0xfd]);
  });

  test('preserves a strict create that appears before snapshot capture',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/appeared.dart');
    final executor = FakeProcessExecutor.success({
      'dart format lib/appeared.dart': 'formatted',
    });
    final fileSystem = _PhaseRaceFileSystem(
      onTemporaryDirectoryCreated: (_) async {
        await target.parent.create(recursive: true);
        await target.writeAsString('concurrent before snapshot');
      },
    );
    final plan = ChangePlan(
      summary: 'guard pre-snapshot create race',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/appeared.dart',
          content: 'generated',
          kind: FileChangeKind.create,
          reason: 'would create',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'lib/appeared.dart'],
          reason: 'must not format concurrent content',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/appeared.dart'));
    expect(report.output, contains('expected file to be absent'));
    expect(target.readAsStringSync(), 'concurrent before snapshot');
  });

  test('preserves a strict create that appears after snapshot observation',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/appeared.dart');
    final executor = FakeProcessExecutor.success({
      'dart format lib/appeared.dart': 'formatted',
    });
    final fileSystem = _PhaseRaceFileSystem(
      onExistsObserved: (path, observation, exists) async {
        if (path == target.path && observation == 3 && !exists) {
          await target.parent.create(recursive: true);
          await target.writeAsString('concurrent after snapshot');
        }
      },
    );
    final plan = ChangePlan(
      summary: 'guard post-snapshot create race',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/appeared.dart',
          content: 'generated',
          kind: FileChangeKind.create,
          reason: 'would create',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'lib/appeared.dart'],
          reason: 'must not format concurrent content',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/appeared.dart'));
    expect(report.output, contains('expected file to be absent'));
    expect(target.readAsStringSync(), 'concurrent after snapshot');
  });

  test('preserves a strict modify changed after snapshot capture', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'previewed'},
    );
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/existing.dart');
    final concurrentBytes = [
      ..._utf8Bom,
      ...utf8.encode('concurrent after snapshot'),
    ];
    final executor = FakeProcessExecutor.success({
      'dart format lib/existing.dart': 'formatted',
    });
    final fileSystem = _PhaseRaceFileSystem(
      onExistsObserved: (path, observation, exists) async {
        if (path == target.path && observation == 3 && exists) {
          await target.writeAsBytes(concurrentBytes);
        }
      },
    );
    final plan = ChangePlan(
      summary: 'guard post-snapshot modify race',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'generated',
          kind: FileChangeKind.modify,
          reason: 'would modify',
          precondition: TextFilePrecondition.exact('previewed'),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'lib/existing.dart'],
          reason: 'must not format concurrent content',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/existing.dart'));
    expect(report.output, contains('original content changed'));
    expect(await target.readAsBytes(), concurrentBytes);
  });

  test('rolls back an earlier create but preserves a later concurrent create',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final first = fixture.file('lib/generated/first.dart');
    final second = fixture.file('lib/generated/second.dart');
    final executor = FakeProcessExecutor({
      'dart format lib/generated/first.dart lib/generated/second.dart':
          const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'must not run',
      ),
    });
    var injected = false;
    final fileSystem = _PhaseRaceFileSystem(
      onAfterWrite: (path) async {
        if (path == first.path && !injected) {
          injected = true;
          await second.writeAsString('concurrent later file');
        }
      },
    );
    final plan = ChangePlan(
      summary: 'selective rollback',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/generated/first.dart',
          content: 'generated first',
          kind: FileChangeKind.create,
          reason: 'create first',
          precondition: TextFilePrecondition.absent(),
        ),
        PlannedFileChange(
          relativePath: 'lib/generated/second.dart',
          content: 'generated second',
          kind: FileChangeKind.create,
          reason: 'create second',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const [
            'format',
            'lib/generated/first.dart',
            'lib/generated/second.dart',
          ],
          reason: 'must not format concurrent content',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(executor.calls, isEmpty);
    expect(first.existsSync(), isFalse);
    expect(second.readAsStringSync(), 'concurrent later file');
    expect(Directory(fixture.file('lib/generated').path).existsSync(), isTrue);
  });

  test('does not format strict content changed after its transaction write',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/generated.dart');
    final executor = FakeProcessExecutor.success({
      'dart format lib/generated.dart': 'formatted',
    });
    var injected = false;
    final fileSystem = _PhaseRaceFileSystem(
      onAfterWrite: (path) async {
        if (path == target.path && !injected) {
          injected = true;
          await target.writeAsString('concurrent after transaction write');
        }
      },
    );
    final plan = ChangePlan(
      summary: 'guard post-write state',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/generated.dart',
          content: 'generated',
          kind: FileChangeKind.create,
          reason: 'create generated file',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'lib/generated.dart'],
          reason: 'must not format concurrent content',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, isEmpty);
    expect(report.output, contains('lib/generated.dart'));
    expect(report.output, contains('changed after transaction write'));
    expect(target.readAsStringSync(), 'concurrent after transaction write');
  });

  test('preserves a concurrent modify change made during selective restore',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'previewed'},
    );
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/existing.dart');
    final concurrentBytes = [
      ..._utf8Bom,
      ...utf8.encode('concurrent during restore'),
    ];
    String? snapshotDirectory;
    final fileSystem = _PhaseRaceFileSystem(
      onTemporaryDirectoryCreated: (path) async {
        snapshotDirectory = path;
      },
      onAfterRead: (path, _) async {
        final snapshot = snapshotDirectory;
        if (snapshot != null &&
            path == '$snapshot${Platform.pathSeparator}file_0') {
          await target.writeAsBytes(concurrentBytes);
        }
      },
    );
    final executor = FakeProcessExecutor({
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      ),
    });
    final plan = ChangePlan(
      summary: 'guard selective modify restore race',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'generated',
          kind: FileChangeKind.modify,
          reason: 'modify existing',
          precondition: TextFilePrecondition.exact('previewed'),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'force rollback',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(await target.readAsBytes(), concurrentBytes);
  });

  test('preserves a concurrent create change made during selective restore',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/keep.txt': 'keep'},
    );
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/created.dart');
    final concurrentBytes = utf8.encode('concurrent during restore');
    var rollbackArmed = false;
    var rollbackLinkChecks = 0;
    final fileSystem = _PhaseRaceFileSystem(
      onIsLinkObserved: (path, _, __) async {
        if (rollbackArmed && path == target.path) {
          rollbackLinkChecks++;
          if (rollbackLinkChecks == 2) {
            await target.writeAsBytes(concurrentBytes);
          }
        }
      },
    );
    final executor = _CallbackProcessExecutor((_) async {
      rollbackArmed = true;
      return const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      );
    });
    final plan = ChangePlan(
      summary: 'guard selective create restore race',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/created.dart',
          content: 'generated',
          kind: FileChangeKind.create,
          reason: 'create file',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'force rollback',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(await target.readAsBytes(), concurrentBytes);
  });

  test('keeps selective rollback when a mutating command fails pre-spawn',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'previewed'},
    );
    addTearDown(fixture.dispose);
    final target = fixture.file('lib/existing.dart');
    final concurrentBytes = utf8.encode('concurrent before spawn');
    final executor = _PreSpawnFailingExecutor(target, concurrentBytes);
    final plan = ChangePlan(
      summary: 'guard pre-spawn failure',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'generated',
          kind: FileChangeKind.modify,
          reason: 'modify existing',
          precondition: TextFilePrecondition.exact('previewed'),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'lib/existing.dart'],
          reason: 'format file',
          mutatesFiles: true,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(executor.calls, 1);
    expect(report.output, contains('spawn failed'));
    expect(await target.readAsBytes(), concurrentBytes);
  });

  test('reports an actual empty-parent cleanup failure as not restored',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/keep.txt': 'keep'},
    );
    addTearDown(fixture.dispose);
    final failingParent = fixture.file('lib/generated').path;
    final fileSystem = _PhaseRaceFileSystem(
      onDeleteEmptyDirectory: (path) async {
        if (path == failingParent) {
          throw FileSystemException('permission denied', path);
        }
      },
    );
    final executor = FakeProcessExecutor({
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      ),
    });
    final plan = ChangePlan(
      summary: 'propagate parent cleanup failure',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/generated/created.dart',
          content: 'generated',
          kind: FileChangeKind.create,
          reason: 'create nested file',
          precondition: TextFilePrecondition.absent(),
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'force rollback',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(report.output, contains('permission denied'));
    expect(fixture.file('lib/generated/created.dart').existsSync(), isFalse);
  });

  test('creates and modifies files and reports successful commands', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'dart format lib': 'Formatted 2 files',
      'flutter analyze': 'No issues found',
    });
    final plan = ChangePlan(
      summary: 'successful example',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'new',
          kind: FileChangeKind.modify,
          reason: 'arrange model',
        ),
        PlannedFileChange(
          relativePath: 'lib/created.dart',
          content: 'created',
          kind: FileChangeKind.create,
          reason: 'new helper',
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'lib'],
          reason: 'format',
          mutatesFiles: true,
        ),
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'verify',
          mutatesFiles: false,
        ),
      ],
      snapshotRoots: const ['lib'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isTrue);
    expect(report.restored, isFalse);
    expect(report.created, ['lib/created.dart']);
    expect(report.modified, ['lib/existing.dart']);
    expect(report.skipped, isEmpty);
    expect(report.output, contains('Formatted 2 files'));
    expect(report.output, contains('No issues found'));
    expect(fixture.file('lib/existing.dart').readAsStringSync(), 'new');
    expect(fixture.file('lib/created.dart').readAsStringSync(), 'created');
    expect(executor.calls, ['dart format lib', 'flutter analyze']);
  });

  test('restores modified files and removes created files after failure',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor({
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      ),
    });
    final plan = ChangePlan(
      summary: 'rollback example',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'new',
          kind: FileChangeKind.modify,
          reason: 'arrange model',
        ),
        PlannedFileChange(
          relativePath: 'lib/created.dart',
          content: 'created',
          kind: FileChangeKind.create,
          reason: 'new helper',
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'verify',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(report.output, contains('analysis failed'));
    expect(fixture.file('lib/existing.dart').readAsStringSync(), 'old');
    expect(fixture.file('lib/created.dart').existsSync(), isFalse);
  });

  test('removes created nested parents but preserves pre-existing ancestors',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'features/keep.txt': 'keep'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor({
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      ),
    });
    final plan = ChangePlan(
      summary: 'nested rollback',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'features/new/deep/created.dart',
          content: 'created',
          kind: FileChangeKind.create,
          reason: 'nested helper',
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'verify',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(
      Directory(fixture.file('features/new').path).existsSync(),
      isFalse,
    );
    expect(Directory(fixture.file('features').path).existsSync(), isTrue);
    expect(fixture.file('features/keep.txt').readAsStringSync(), 'keep');
  });

  test('restores declared snapshot roots changed by a failed command',
      () async {
    final fixture = await ProjectFixture.create(
      files: {
        'generated/existing.txt': 'before',
        'unrelated.txt': 'untouched',
      },
    );
    addTearDown(fixture.dispose);
    final executor = _CallbackProcessExecutor((workingDirectory) async {
      await File(
        '${workingDirectory.path}/generated/existing.txt',
      ).writeAsString('after');
      await File(
        '${workingDirectory.path}/generated/created.txt',
      ).writeAsString('new');
      return const ProcessOutput(
        exitCode: 1,
        stdout: 'generation output',
        stderr: 'generation failed',
      );
    });
    final plan = ChangePlan(
      summary: 'generated rollback',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', 'generated'],
          reason: 'generate',
          mutatesFiles: true,
        ),
      ],
      snapshotRoots: const ['generated'],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(
      fixture.file('generated/existing.txt').readAsStringSync(),
      'before',
    );
    expect(fixture.file('generated/created.txt').existsSync(), isFalse);
    expect(fixture.file('unrelated.txt').readAsStringSync(), 'untouched');
    expect(
      report.output,
      allOf(contains('generation output'), contains('generation failed')),
    );
  });

  test('stops commands after the first nonzero exit code', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor({
      'dart first': const ProcessOutput(
        exitCode: 2,
        stdout: 'first stdout',
        stderr: 'first stderr',
      ),
      'dart second': const ProcessOutput(
        exitCode: 0,
        stdout: 'second stdout',
        stderr: '',
      ),
    });
    final plan = ChangePlan(
      summary: 'stop after failure',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['first'],
          reason: 'first',
          mutatesFiles: false,
        ),
        PlannedCommand(
          executable: 'dart',
          arguments: const ['second'],
          reason: 'second',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(executor.calls, ['dart first']);
    expect(report.output, contains('first stdout'));
    expect(report.output, contains('first stderr'));
    expect(report.output, isNot(contains('second stdout')));
  });

  test('captures stdout and stderr exactly in command order', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor({
      'dart first': const ProcessOutput(
        exitCode: 0,
        stdout: 'first stdout\n',
        stderr: 'first stderr\n',
      ),
      'dart second': const ProcessOutput(
        exitCode: 0,
        stdout: 'second stdout\n',
        stderr: 'second stderr\n',
      ),
    });
    final plan = ChangePlan(
      summary: 'ordered output',
      projectRoot: fixture.root,
      commands: [
        PlannedCommand(
          executable: 'dart',
          arguments: const ['first'],
          reason: 'first',
          mutatesFiles: false,
        ),
        PlannedCommand(
          executable: 'dart',
          arguments: const ['second'],
          reason: 'second',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isTrue);
    expect(
      report.output,
      'first stdout\nfirst stderr\nsecond stdout\nsecond stderr\n',
    );
  });

  test('reports a restore failure without hiding the command failure',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor({
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'analysis failed',
      ),
    });
    final fileSystem = _FailingRestoreFileSystem(
      fixture.file('lib/existing.dart').path,
    );
    final plan = ChangePlan(
      summary: 'failed restoration',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'new',
          kind: FileChangeKind.modify,
          reason: 'change existing',
        ),
        PlannedFileChange(
          relativePath: 'lib/created.dart',
          content: 'created',
          kind: FileChangeKind.create,
          reason: 'create helper',
        ),
      ],
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'verify',
          mutatesFiles: false,
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: executor,
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(report.output, contains('analysis failed'));
    expect(report.output, contains('Command failed (1): flutter analyze'));
    expect(report.output, contains('restore failed'));
    expect(fixture.file('lib/created.dart').existsSync(), isFalse);
  });

  test('deletes its snapshot directory after a successful transaction',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    final fileSystem = _TrackingSnapshotFileSystem();
    addTearDown(fixture.dispose);
    addTearDown(fileSystem.dispose);
    final plan = ChangePlan(
      summary: 'successful cleanup',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'new',
          kind: FileChangeKind.modify,
          reason: 'change existing',
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isTrue);
    expect(fileSystem.snapshotDirectory, isNotNull);
    expect(
      await fileSystem.exists(fileSystem.snapshotDirectory!),
      isFalse,
    );
  });

  test('reports snapshot cleanup failure without rolling back writes',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/existing.dart': 'old'},
    );
    final fileSystem = _TrackingSnapshotFileSystem(failCleanup: true);
    addTearDown(fixture.dispose);
    addTearDown(fileSystem.dispose);
    final plan = ChangePlan(
      summary: 'failed cleanup',
      projectRoot: fixture.root,
      files: const [
        PlannedFileChange(
          relativePath: 'lib/existing.dart',
          content: 'new',
          kind: FileChangeKind.modify,
          reason: 'change existing',
        ),
      ],
    );

    final report = await ChangeTransaction(
      executor: FakeProcessExecutor(const {}),
      fileSystem: fileSystem,
    ).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isFalse);
    expect(fixture.file('lib/existing.dart').readAsStringSync(), 'new');
    expect(report.output, contains('snapshot cleanup failed'));
  });
}

const _utf8Bom = [0xef, 0xbb, 0xbf];

final class _CallbackProcessExecutor implements ProcessExecutor {
  _CallbackProcessExecutor(this.callback);

  final Future<ProcessOutput> Function(Directory workingDirectory) callback;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) {
    onStarted?.call();
    return callback(workingDirectory);
  }
}

final class _PreSpawnFailingExecutor implements ProcessExecutor {
  _PreSpawnFailingExecutor(this.target, this.concurrentBytes);

  final File target;
  final List<int> concurrentBytes;
  var calls = 0;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) async {
    calls++;
    await target.writeAsBytes(concurrentBytes);
    throw ProcessException(executable, arguments, 'spawn failed');
  }
}

final class _FailingRestoreFileSystem implements ProjectFileSystem {
  _FailingRestoreFileSystem(this.restorePath);

  final String restorePath;
  final ProjectFileSystem _delegate = const LocalProjectFileSystem();
  var _writesToRestorePath = 0;

  @override
  Future<String> createTemporaryDirectory(String prefix) =>
      _delegate.createTemporaryDirectory(prefix);

  @override
  Future<void> copyTree(String source, String destination) =>
      _delegate.copyTree(source, destination);

  @override
  Future<void> delete(String path) => _delegate.delete(path);

  @override
  Future<bool> deleteEmptyDirectory(String path) =>
      _delegate.deleteEmptyDirectory(path);

  @override
  Future<bool> exists(String path) => _delegate.exists(path);

  @override
  Future<bool> isLink(String path) => _delegate.isLink(path);

  @override
  Future<bool> containsLink(String path) => _delegate.containsLink(path);

  @override
  Future<List<int>> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    if (path == restorePath && _writesToRestorePath++ == 1) {
      throw const FileSystemException('restore failed');
    }
    return _delegate.writeBytes(path, bytes);
  }
}

final class _TrackingSnapshotFileSystem implements ProjectFileSystem {
  _TrackingSnapshotFileSystem({this.failCleanup = false});

  final bool failCleanup;
  final ProjectFileSystem _delegate = const LocalProjectFileSystem();
  String? snapshotDirectory;

  @override
  Future<String> createTemporaryDirectory(String prefix) async {
    final path = (await Directory.systemTemp.createTemp(prefix)).path;
    snapshotDirectory = path;
    return path;
  }

  Future<void> dispose() async {
    final path = snapshotDirectory;
    if (path != null && await _delegate.exists(path)) {
      await _delegate.delete(path);
    }
  }

  @override
  Future<bool> containsLink(String path) => _delegate.containsLink(path);

  @override
  Future<void> copyTree(String source, String destination) =>
      _delegate.copyTree(source, destination);

  @override
  Future<void> delete(String path) {
    if (failCleanup && path == snapshotDirectory) {
      throw const FileSystemException('snapshot cleanup failed');
    }
    return _delegate.delete(path);
  }

  @override
  Future<bool> deleteEmptyDirectory(String path) =>
      _delegate.deleteEmptyDirectory(path);

  @override
  Future<bool> exists(String path) => _delegate.exists(path);

  @override
  Future<bool> isLink(String path) => _delegate.isLink(path);

  @override
  Future<List<int>> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _delegate.writeBytes(path, bytes);
}

typedef _TemporaryDirectoryCallback = Future<void> Function(String path);
typedef _ExistsObservedCallback = Future<void> Function(
  String path,
  int observation,
  bool exists,
);
typedef _WriteCallback = Future<void> Function(String path);
typedef _ReadCallback = Future<void> Function(String path, List<int> bytes);
typedef _IsLinkObservedCallback = Future<void> Function(
  String path,
  int observation,
  bool isLink,
);
typedef _DeleteEmptyDirectoryCallback = Future<void> Function(String path);

final class _PhaseRaceFileSystem implements ProjectFileSystem {
  _PhaseRaceFileSystem({
    this.onTemporaryDirectoryCreated,
    this.onExistsObserved,
    this.onAfterWrite,
    this.onAfterRead,
    this.onIsLinkObserved,
    this.onDeleteEmptyDirectory,
  });

  final _TemporaryDirectoryCallback? onTemporaryDirectoryCreated;
  final _ExistsObservedCallback? onExistsObserved;
  final _WriteCallback? onAfterWrite;
  final _ReadCallback? onAfterRead;
  final _IsLinkObservedCallback? onIsLinkObserved;
  final _DeleteEmptyDirectoryCallback? onDeleteEmptyDirectory;
  final ProjectFileSystem _delegate = const LocalProjectFileSystem();
  final Map<String, int> _existenceObservations = {};
  final Map<String, int> _linkObservations = {};

  @override
  Future<String> createTemporaryDirectory(String prefix) async {
    final path = await _delegate.createTemporaryDirectory(prefix);
    await onTemporaryDirectoryCreated?.call(path);
    return path;
  }

  @override
  Future<bool> containsLink(String path) => _delegate.containsLink(path);

  @override
  Future<void> copyTree(String source, String destination) =>
      _delegate.copyTree(source, destination);

  @override
  Future<void> delete(String path) => _delegate.delete(path);

  @override
  Future<bool> deleteEmptyDirectory(String path) async {
    await onDeleteEmptyDirectory?.call(path);
    return _delegate.deleteEmptyDirectory(path);
  }

  @override
  Future<bool> exists(String path) async {
    final result = await _delegate.exists(path);
    final observation = (_existenceObservations[path] ?? 0) + 1;
    _existenceObservations[path] = observation;
    await onExistsObserved?.call(path, observation, result);
    return result;
  }

  @override
  Future<bool> isLink(String path) async {
    final result = await _delegate.isLink(path);
    final observation = (_linkObservations[path] ?? 0) + 1;
    _linkObservations[path] = observation;
    await onIsLinkObserved?.call(path, observation, result);
    return result;
  }

  @override
  Future<List<int>> readBytes(String path) async {
    final bytes = await _delegate.readBytes(path);
    await onAfterRead?.call(path, bytes);
    return bytes;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await _delegate.writeBytes(path, bytes);
    await onAfterWrite?.call(path);
  }
}
