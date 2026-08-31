import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../process/process_executor.dart';
import 'change_plan.dart';
import 'change_report.dart';
import 'project_file_system.dart';

final class ChangeTransaction {
  ChangeTransaction({
    required this.executor,
    ProjectFileSystem? fileSystem,
  }) : fileSystem = fileSystem ?? const LocalProjectFileSystem();

  final ProcessExecutor executor;
  final ProjectFileSystem fileSystem;

  Future<ChangeReport> execute(ChangePlan plan) async {
    final created = <String>[];
    final modified = <String>[];
    final skipped = <String>[];
    final output = <String>[];
    final snapshots = <_Snapshot>[];
    final snapshotDirectory = await Directory.systemTemp.createTemp(
      'gold_change_transaction_',
    );
    Object? rootFailure;
    var restored = false;

    try {
      await _snapshot(plan, snapshotDirectory, snapshots);

      for (final change in plan.files) {
        final path = p.join(plan.projectRoot.path, change.relativePath);
        final exists = await fileSystem.exists(path);
        if ((change.kind == FileChangeKind.create && exists) ||
            (change.kind == FileChangeKind.modify && !exists)) {
          skipped.add(change.relativePath);
          continue;
        }

        await fileSystem.writeBytes(path, utf8.encode(change.content));
        switch (change.kind) {
          case FileChangeKind.create:
            created.add(change.relativePath);
          case FileChangeKind.modify:
            modified.add(change.relativePath);
        }
      }

      for (final command in plan.commands) {
        final result = await executor.run(
          command.executable,
          command.arguments,
          workingDirectory: plan.projectRoot,
        );
        _appendOutput(output, result.stdout);
        _appendOutput(output, result.stderr);
        if (result.exitCode != 0) {
          final failure = _CommandFailure(
            command.executable,
            command.arguments,
            result.exitCode,
          );
          rootFailure = failure;
          _appendOutput(output, failure.toString());
          break;
        }
      }
    } catch (error) {
      rootFailure = error;
      _appendOutput(output, error.toString());
    } finally {
      if (rootFailure != null) {
        try {
          await _restore(snapshots);
          restored = true;
        } catch (error) {
          _appendOutput(output, error.toString());
        }
      }
      try {
        if (await snapshotDirectory.exists()) {
          await snapshotDirectory.delete(recursive: true);
        }
      } catch (error) {
        _appendOutput(output, error.toString());
      }
    }

    return ChangeReport(
      success: rootFailure == null,
      restored: restored,
      created: created,
      modified: modified,
      skipped: skipped,
      output: output.join('\n'),
    );
  }

  Future<void> _snapshot(
    ChangePlan plan,
    Directory snapshotDirectory,
    List<_Snapshot> snapshots,
  ) async {
    var index = 0;
    for (final change in plan.files) {
      final original = p.join(plan.projectRoot.path, change.relativePath);
      final backup = p.join(snapshotDirectory.path, 'file_${index++}');
      final existed = await fileSystem.exists(original);
      if (existed) {
        await fileSystem.copyTree(original, backup);
      }
      snapshots.add(
        _Snapshot(
          original: original,
          backup: backup,
          existed: existed,
          isRoot: false,
        ),
      );
    }
    for (final relativeRoot in plan.snapshotRoots) {
      final original = p.join(plan.projectRoot.path, relativeRoot);
      final backup = p.join(snapshotDirectory.path, 'root_${index++}');
      final existed = await fileSystem.exists(original);
      if (existed) {
        await fileSystem.copyTree(original, backup);
      }
      snapshots.add(
        _Snapshot(
          original: original,
          backup: backup,
          existed: existed,
          isRoot: true,
        ),
      );
    }
  }

  Future<void> _restore(List<_Snapshot> snapshots) async {
    final failures = <Object>[];
    for (final snapshot in snapshots.where((entry) => entry.isRoot)) {
      try {
        if (await fileSystem.exists(snapshot.original)) {
          await fileSystem.delete(snapshot.original);
        }
        if (snapshot.existed) {
          await fileSystem.copyTree(snapshot.backup, snapshot.original);
        }
      } catch (error) {
        failures.add(error);
      }
    }
    for (final snapshot in snapshots.where((entry) => !entry.isRoot)) {
      try {
        if (snapshot.existed) {
          final bytes = await fileSystem.readBytes(snapshot.backup);
          await fileSystem.writeBytes(snapshot.original, bytes);
        } else if (await fileSystem.exists(snapshot.original)) {
          await fileSystem.delete(snapshot.original);
        }
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw _RestorationFailure(failures);
    }
  }

  static void _appendOutput(List<String> output, String value) {
    if (value.isNotEmpty) {
      output.add(value);
    }
  }
}

final class _Snapshot {
  const _Snapshot({
    required this.original,
    required this.backup,
    required this.existed,
    required this.isRoot,
  });

  final String original;
  final String backup;
  final bool existed;
  final bool isRoot;
}

final class _CommandFailure {
  const _CommandFailure(this.executable, this.arguments, this.exitCode);

  final String executable;
  final List<String> arguments;
  final int exitCode;

  @override
  String toString() =>
      'Command failed ($exitCode): ${[executable, ...arguments].join(' ')}';
}

final class _RestorationFailure {
  _RestorationFailure(Iterable<Object> failures)
      : failures = List.unmodifiable(failures);

  final List<Object> failures;

  @override
  String toString() => failures.join('\n');
}
