import 'dart:convert';

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
    final createdParentDirectories = <String>[];
    String? snapshotDirectory;
    Object? rootFailure;
    var restored = false;
    var mutationStarted = false;

    try {
      await _validateMutatingCommands(plan);
      await _validateDeclaredPaths(plan);
      await _recordMissingParentDirectories(
        plan,
        createdParentDirectories,
      );
      snapshotDirectory = await fileSystem.createTemporaryDirectory(
        'gold_change_transaction_',
      );
      await _snapshot(plan, snapshotDirectory, snapshots);

      for (final change in plan.files) {
        final path = p.join(plan.projectRoot.path, change.relativePath);
        await _rejectLinks(plan, change.relativePath);
        final exists = await fileSystem.exists(path);
        if ((change.kind == FileChangeKind.create && exists) ||
            (change.kind == FileChangeKind.modify && !exists)) {
          skipped.add(change.relativePath);
          continue;
        }

        mutationStarted = true;
        await fileSystem.writeBytes(path, utf8.encode(change.content));
        switch (change.kind) {
          case FileChangeKind.create:
            created.add(change.relativePath);
          case FileChangeKind.modify:
            modified.add(change.relativePath);
        }
      }

      for (final command in plan.commands) {
        if (command.mutatesFiles) {
          mutationStarted = true;
        }
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
          _appendDiagnostic(output, failure.toString());
          break;
        }
      }
    } catch (error) {
      rootFailure = error;
      _appendDiagnostic(output, error.toString());
    } finally {
      if (rootFailure != null && mutationStarted) {
        try {
          await _restore(
            plan.projectRoot.path,
            snapshots,
            createdParentDirectories,
          );
          restored = true;
        } catch (error) {
          _appendDiagnostic(output, error.toString());
        }
      }
      final cleanupPath = snapshotDirectory;
      if (cleanupPath != null) {
        try {
          if (await fileSystem.exists(cleanupPath)) {
            await fileSystem.delete(cleanupPath);
          }
        } catch (error) {
          rootFailure ??= error;
          _appendDiagnostic(output, error.toString());
        }
      }
    }

    return ChangeReport(
      success: rootFailure == null,
      restored: restored,
      created: created,
      modified: modified,
      skipped: skipped,
      output: output.join(),
    );
  }

  Future<void> _snapshot(
    ChangePlan plan,
    String snapshotDirectory,
    List<_Snapshot> snapshots,
  ) async {
    var index = 0;
    for (final change in plan.files) {
      await _rejectLinks(plan, change.relativePath);
      final original = p.join(plan.projectRoot.path, change.relativePath);
      final backup = p.join(snapshotDirectory, 'file_${index++}');
      final existed = await fileSystem.exists(original);
      if (existed) {
        await fileSystem.copyTree(original, backup);
      }
      snapshots.add(
        _Snapshot(
          projectRoot: plan.projectRoot.path,
          original: original,
          backup: backup,
          existed: existed,
          isRoot: false,
        ),
      );
    }
    for (final relativeRoot in plan.snapshotRoots) {
      await _rejectLinks(plan, relativeRoot, recursive: true);
      final original = p.join(plan.projectRoot.path, relativeRoot);
      final backup = p.join(snapshotDirectory, 'root_${index++}');
      final existed = await fileSystem.exists(original);
      if (existed) {
        await fileSystem.copyTree(original, backup);
      }
      snapshots.add(
        _Snapshot(
          projectRoot: plan.projectRoot.path,
          original: original,
          backup: backup,
          existed: existed,
          isRoot: true,
        ),
      );
    }
  }

  Future<void> _restore(
    String projectRoot,
    List<_Snapshot> snapshots,
    List<String> createdParentDirectories,
  ) async {
    final failures = <Object>[];
    for (final snapshot in snapshots.where((entry) => entry.isRoot)) {
      try {
        await _rejectAbsoluteProjectPath(
          snapshot.projectRoot,
          snapshot.original,
          recursive: true,
        );
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
        await _rejectAbsoluteProjectPath(
          snapshot.projectRoot,
          snapshot.original,
        );
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
    final parents = [...createdParentDirectories]..sort(
        (left, right) => p.split(right).length.compareTo(p.split(left).length),
      );
    for (final parent in parents) {
      try {
        await _rejectAbsoluteProjectPath(
          projectRoot,
          parent,
          recursive: true,
        );
        if (await fileSystem.exists(parent)) {
          await fileSystem.delete(parent);
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

  static void _appendDiagnostic(List<String> output, String value) {
    if (value.isEmpty) {
      return;
    }
    if (output.isNotEmpty && !output.last.endsWith('\n')) {
      output.add('\n');
    }
    output.add(value);
  }

  Future<void> _validateDeclaredPaths(ChangePlan plan) async {
    for (final change in plan.files) {
      await _rejectLinks(plan, change.relativePath);
    }
    for (final root in plan.snapshotRoots) {
      await _rejectLinks(plan, root, recursive: true);
    }
  }

  Future<void> _recordMissingParentDirectories(
    ChangePlan plan,
    List<String> missingParents,
  ) async {
    final seen = <String>{};
    for (final change in plan.files) {
      var current = plan.projectRoot.path;
      final segments = p.split(change.relativePath);
      for (final segment in segments.take(segments.length - 1)) {
        current = p.join(current, segment);
        if (!await fileSystem.exists(current) && seen.add(current)) {
          missingParents.add(current);
        }
      }
    }
  }

  Future<void> _rejectLinks(
    ChangePlan plan,
    String relativePath, {
    bool recursive = false,
  }) =>
      _rejectAbsoluteProjectPath(
        plan.projectRoot.path,
        p.join(plan.projectRoot.path, relativePath),
        relativePath: relativePath,
        recursive: recursive,
      );

  Future<void> _rejectAbsoluteProjectPath(
    String projectRoot,
    String target, {
    String? relativePath,
    bool recursive = false,
  }) async {
    final displayPath = relativePath ?? p.relative(target, from: projectRoot);
    if (await fileSystem.isLink(projectRoot)) {
      throw StateError(
        'Project path contains a symbolic link: $displayPath',
      );
    }
    var current = projectRoot;
    for (final segment in p.split(displayPath)) {
      if (segment == '.') {
        continue;
      }
      current = p.join(current, segment);
      if (await fileSystem.isLink(current)) {
        throw StateError(
          'Project path contains a symbolic link: $displayPath',
        );
      }
    }
    if (recursive &&
        await fileSystem.exists(target) &&
        await fileSystem.containsLink(target)) {
      throw StateError(
        'Snapshot root contains a symbolic link: $displayPath',
      );
    }
  }

  Future<void> _validateMutatingCommands(ChangePlan plan) async {
    for (final command in plan.commands.where((entry) => entry.mutatesFiles)) {
      for (final argument in command.arguments) {
        if (_hasUnsafeCommandCharacters(argument)) {
          throw StateError(
            'Mutating command has unsafe argument: $argument',
          );
        }
      }
      if (command.executable == 'dart' &&
          command.arguments.firstOrNull == 'format') {
        _validateDartFormat(plan, command.arguments);
      } else if (command.executable == 'dart' &&
          _startsWith(
              command.arguments, const ['run', 'build_runner', 'build'])) {
        await _validateBuildRunner(plan, command.arguments);
      } else if ((command.executable == 'dart' ||
              command.executable == 'flutter') &&
          _startsWith(command.arguments, const ['pub', 'get'])) {
        _validatePubGet(plan, command.arguments);
      } else if (command.executable != 'dart' &&
          command.executable != 'flutter') {
        throw StateError(
          'Unsupported mutating executable: ${command.executable}',
        );
      } else {
        throw StateError(
          'Unsupported mutating command form: '
          '${[command.executable, ...command.arguments].join(' ')}',
        );
      }
    }
  }

  static void _validateDartFormat(
    ChangePlan plan,
    List<String> arguments,
  ) {
    final targets = <String>[];
    for (final argument in arguments.skip(1)) {
      if (!argument.startsWith('-')) {
        _validatePositionalPath(argument);
        targets.add(p.normalize(argument));
        continue;
      }
      if (argument == '--fix' || argument == '--set-exit-if-changed') {
        continue;
      }
      if (argument.startsWith('--output=')) {
        final value = argument.substring('--output='.length);
        if (value == 'show' || value == 'json' || value == 'none') {
          continue;
        }
      }
      if (argument.startsWith('--line-length=') ||
          argument.startsWith('--page-width=')) {
        final value = argument.substring(argument.indexOf('=') + 1);
        if (RegExp(r'^\d+$').hasMatch(value)) {
          continue;
        }
      }
      throw StateError('Unsupported dart format option: $argument');
    }
    if (targets.isEmpty) {
      throw StateError('Mutating dart format requires a declared target');
    }
    _requireCoverage(plan, targets);
  }

  Future<void> _validateBuildRunner(
    ChangePlan plan,
    List<String> arguments,
  ) async {
    for (final argument in arguments.skip(3)) {
      if (argument != '--delete-conflicting-outputs') {
        throw StateError('Unsupported build runner option: $argument');
      }
    }
    final targets = <String>['pubspec.yaml', 'pubspec.lock'];
    for (final sourceRoot in const ['lib', 'test']) {
      final path = p.join(plan.projectRoot.path, sourceRoot);
      if (await fileSystem.exists(path)) {
        targets.add(sourceRoot);
      }
    }
    _requireCoverage(plan, targets);
  }

  static void _validatePubGet(
    ChangePlan plan,
    List<String> arguments,
  ) {
    const supportedOptions = {
      '--offline',
      '--enforce-lockfile',
      '--no-example',
    };
    for (final argument in arguments.skip(2)) {
      if (!supportedOptions.contains(argument)) {
        throw StateError('Unsupported pub get option: $argument');
      }
    }
    _requireCoverage(plan, const ['pubspec.yaml', 'pubspec.lock']);
  }

  static void _requireCoverage(ChangePlan plan, Iterable<String> targets) {
    final uncovered = targets
        .map(p.normalize)
        .where((target) => !_isCovered(plan, target))
        .toList();
    if (uncovered.isNotEmpty) {
      throw StateError(
        'Mutating command targets are not covered by rollback coverage: '
        '${uncovered.join(', ')}',
      );
    }
  }

  static bool _isCovered(ChangePlan plan, String target) {
    if (plan.files.any((file) => file.relativePath == target)) {
      return true;
    }
    return plan.snapshotRoots.any((root) {
      final relative = p.normalize(p.relative(target, from: root));
      return relative == '.' ||
          (relative != '..' && !relative.startsWith('..${p.separator}'));
    });
  }

  static void _validatePositionalPath(String value) {
    if (p.posix.isAbsolute(value) ||
        p.windows.isAbsolute(value) ||
        RegExp(r'(^|[\\/])\.\.([\\/]|$)').hasMatch(value)) {
      throw StateError('Mutating command has unsafe path argument: $value');
    }
  }

  static bool _hasUnsafeCommandCharacters(String value) {
    if (value.contains('\u0000') ||
        value.contains('\n') ||
        value.contains('\r') ||
        RegExp(r'[;&|<>`]').hasMatch(value) ||
        value.contains(r'$(')) {
      return true;
    }
    return false;
  }

  static bool _startsWith(List<String> values, List<String> prefix) {
    if (values.length < prefix.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index++) {
      if (values[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }
}

final class _Snapshot {
  const _Snapshot({
    required this.projectRoot,
    required this.original,
    required this.backup,
    required this.existed,
    required this.isRoot,
  });

  final String projectRoot;
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
