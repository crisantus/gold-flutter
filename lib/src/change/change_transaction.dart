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
    final writtenFiles = <String, List<int>>{};
    final createdParentDirectories = <String>{};
    String? snapshotDirectory;
    Object? rootFailure;
    var restored = false;
    var mutatingCommandStarted = false;

    try {
      final commandEffects = await _validateCommands(plan);
      await _validateDeclaredPaths(plan);
      await _validatePreconditions(plan);
      snapshotDirectory = await fileSystem.createTemporaryDirectory(
        'gold_change_transaction_',
      );
      await _snapshot(plan, snapshotDirectory, snapshots);
      await _validatePreconditions(plan);

      for (final change in plan.files) {
        late final String path;
        late final List<String> missingParents;
        if (change.precondition case final precondition?) {
          missingParents = await _missingParentDirectories(plan, change);
          path = await _validatePrecondition(plan, change, precondition);
        } else {
          var unguardedPath = await _rejectLinks(plan, change.relativePath);
          final exists = await fileSystem.exists(unguardedPath);
          if ((change.kind == FileChangeKind.create && exists) ||
              (change.kind == FileChangeKind.modify && !exists)) {
            skipped.add(change.relativePath);
            continue;
          }
          missingParents = await _missingParentDirectories(plan, change);
          unguardedPath = await _rejectLinks(plan, change.relativePath);
          path = unguardedPath;
        }

        final bytes = utf8.encode(change.content);
        // A non-cooperating process can still race the final validation and
        // atomic replacement; there is no portable compare-and-swap file API.
        await fileSystem.writeBytes(path, bytes);
        writtenFiles[change.relativePath] = List.unmodifiable(bytes);
        createdParentDirectories.addAll(missingParents);
        switch (change.kind) {
          case FileChangeKind.create:
            created.add(change.relativePath);
          case FileChangeKind.modify:
            modified.add(change.relativePath);
        }
      }

      for (var index = 0; index < plan.commands.length; index++) {
        final command = plan.commands[index];
        void Function()? onStarted;
        if (commandEffects[index] == _CommandEffect.mutating &&
            !mutatingCommandStarted) {
          await _validatePostWriteState(plan, writtenFiles);
          onStarted = () {
            mutatingCommandStarted = true;
          };
        }
        final result = await executor.run(
          command.executable,
          command.arguments,
          workingDirectory: plan.projectRoot,
          onStarted: onStarted,
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
      if (rootFailure != null &&
          (writtenFiles.isNotEmpty || mutatingCommandStarted)) {
        try {
          final rollbackSnapshots = mutatingCommandStarted
              ? snapshots
              : snapshots
                  .where(
                    (snapshot) =>
                        !snapshot.isRoot &&
                        writtenFiles.containsKey(snapshot.relativePath),
                  )
                  .toList();
          restored = await _restore(
            plan.projectRoot.path,
            snapshotDirectory!,
            rollbackSnapshots,
            createdParentDirectories,
            expectedOwnedContents: mutatingCommandStarted ? null : writtenFiles,
          );
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
      var original = await _rejectLinks(plan, change.relativePath);
      final backupName = 'file_${index++}';
      final existed = await fileSystem.exists(original);
      if (existed) {
        original = await _rejectLinks(plan, change.relativePath);
        final checkedBackup = _resolveContainedPath(
          snapshotDirectory,
          backupName,
        );
        await fileSystem.copyTree(original, checkedBackup);
      }
      snapshots.add(
        _Snapshot(
          relativePath: change.relativePath,
          backupName: backupName,
          existed: existed,
          isRoot: false,
        ),
      );
    }
    for (final relativeRoot in plan.snapshotRoots) {
      var original = await _rejectLinks(
        plan,
        relativeRoot,
        recursive: true,
      );
      final backupName = 'root_${index++}';
      final existed = await fileSystem.exists(original);
      if (existed) {
        original = await _rejectLinks(plan, relativeRoot, recursive: true);
        final checkedBackup = _resolveContainedPath(
          snapshotDirectory,
          backupName,
        );
        await fileSystem.copyTree(original, checkedBackup);
      }
      snapshots.add(
        _Snapshot(
          relativePath: relativeRoot,
          backupName: backupName,
          existed: existed,
          isRoot: true,
        ),
      );
    }
  }

  Future<bool> _restore(
    String projectRoot,
    String snapshotDirectory,
    List<_Snapshot> snapshots,
    Set<String> createdParentDirectories, {
    required Map<String, List<int>>? expectedOwnedContents,
  }) async {
    final failures = <Object>[];
    var restored = false;
    for (final snapshot in snapshots.where((entry) => entry.isRoot)) {
      try {
        var original = await _rejectProjectPath(
          projectRoot,
          snapshot.relativePath,
          recursive: true,
        );
        if (await fileSystem.exists(original)) {
          original = await _rejectProjectPath(
            projectRoot,
            snapshot.relativePath,
            recursive: true,
          );
          await fileSystem.delete(original);
          restored = true;
        }
        if (snapshot.existed) {
          final backup = _resolveContainedPath(
            snapshotDirectory,
            snapshot.backupName,
          );
          original = await _rejectProjectPath(
            projectRoot,
            snapshot.relativePath,
            recursive: true,
          );
          await fileSystem.copyTree(backup, original);
          restored = true;
        }
      } catch (error) {
        failures.add(error);
      }
    }
    for (final snapshot in snapshots.where((entry) => !entry.isRoot)) {
      try {
        var original = await _rejectProjectPath(
          projectRoot,
          snapshot.relativePath,
        );
        final expectedOwnedContent =
            expectedOwnedContents?[snapshot.relativePath];
        if (expectedOwnedContents != null &&
            (expectedOwnedContent == null ||
                !await _matchesBytes(original, expectedOwnedContent))) {
          continue;
        }
        if (snapshot.existed) {
          final backup = _resolveContainedPath(
            snapshotDirectory,
            snapshot.backupName,
          );
          final bytes = await fileSystem.readBytes(backup);
          original = await _rejectProjectPath(
            projectRoot,
            snapshot.relativePath,
          );
          if (expectedOwnedContent != null &&
              !await _matchesBytes(original, expectedOwnedContent)) {
            continue;
          }
          await fileSystem.writeBytes(original, bytes);
          restored = true;
        } else if (await fileSystem.exists(original)) {
          original = await _rejectProjectPath(
            projectRoot,
            snapshot.relativePath,
          );
          if (expectedOwnedContent != null &&
              !await _matchesBytes(original, expectedOwnedContent)) {
            continue;
          }
          await fileSystem.delete(original);
          restored = true;
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
        final parentPath = await _rejectProjectPath(
          projectRoot,
          parent,
        );
        if (await fileSystem.deleteEmptyDirectory(parentPath)) {
          restored = true;
        }
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw _RestorationFailure(failures);
    }
    return restored;
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

  Future<void> _validatePreconditions(ChangePlan plan) async {
    for (final change in plan.files) {
      final precondition = change.precondition;
      if (precondition == null) {
        continue;
      }
      await _validatePrecondition(plan, change, precondition);
    }
  }

  Future<String> _validatePrecondition(
    ChangePlan plan,
    PlannedFileChange change,
    TextFilePrecondition precondition,
  ) async {
    final path = await _rejectLinks(plan, change.relativePath);
    final exists = await fileSystem.exists(path);
    switch (precondition.kind) {
      case TextFilePreconditionKind.absent:
        if (exists) {
          throw StateError(
            'File precondition failed for ${change.relativePath}: '
            'expected file to be absent.',
          );
        }
      case TextFilePreconditionKind.exactContent:
        if (!exists) {
          throw StateError(
            'File precondition failed for ${change.relativePath}: '
            'expected original content but file is missing.',
          );
        }
        final bytes = await fileSystem.readBytes(path);
        late final String actualContent;
        try {
          actualContent = utf8.decode(bytes);
        } on FormatException {
          throw StateError(
            'File precondition failed for ${change.relativePath}: '
            'actual file contains invalid UTF-8 text.',
          );
        }
        if (actualContent != precondition.expectedContent!) {
          throw StateError(
            'File precondition failed for ${change.relativePath}: '
            'original content changed after planning.',
          );
        }
    }
    return path;
  }

  Future<void> _validatePostWriteState(
    ChangePlan plan,
    Map<String, List<int>> writtenFiles,
  ) async {
    for (final change in plan.files) {
      final expectedBytes = writtenFiles[change.relativePath];
      if (expectedBytes == null) {
        if (change.precondition != null) {
          throw StateError(
            'File changed after transaction write for '
            '${change.relativePath}: strict change was not written.',
          );
        }
        continue;
      }
      final path = await _rejectLinks(plan, change.relativePath);
      if (!await _matchesBytes(path, expectedBytes)) {
        throw StateError(
          'File changed after transaction write for ${change.relativePath}: '
          'refusing to start a mutating command.',
        );
      }
    }
  }

  Future<bool> _matchesBytes(String path, List<int> expected) async {
    if (!await fileSystem.exists(path)) {
      return false;
    }
    try {
      return _bytesEqual(await fileSystem.readBytes(path), expected);
    } on FileSystemException {
      return false;
    }
  }

  Future<List<String>> _missingParentDirectories(
    ChangePlan plan,
    PlannedFileChange change,
  ) async {
    final missingParents = <String>[];
    var current = '.';
    final relativePath = ChangePlan.normalizeRelativePath(
      change.relativePath,
    );
    final segments = p.posix.split(relativePath);
    for (final segment in segments.take(segments.length - 1)) {
      current = p.posix.join(current, segment);
      final target = _resolveProjectPath(plan.projectRoot.path, current);
      if (!await fileSystem.exists(target)) {
        missingParents.add(current);
      }
    }
    return missingParents;
  }

  Future<String> _rejectLinks(
    ChangePlan plan,
    String relativePath, {
    bool recursive = false,
  }) =>
      _rejectProjectPath(
        plan.projectRoot.path,
        relativePath,
        recursive: recursive,
      );

  Future<String> _rejectProjectPath(
    String projectRoot,
    String relativePath, {
    bool recursive = false,
  }) async {
    final displayPath = ChangePlan.normalizeRelativePath(relativePath);
    final root = p.normalize(p.absolute(projectRoot));
    final target = _resolveProjectPath(root, displayPath);
    if (await fileSystem.isLink(root)) {
      throw StateError(
        'Project path contains a symbolic link: $displayPath',
      );
    }
    var current = root;
    for (final segment in p.posix.split(displayPath)) {
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
    return target;
  }

  static String _resolveProjectPath(String projectRoot, String relativePath) {
    final normalized = ChangePlan.normalizeRelativePath(relativePath);
    final root = p.normalize(p.absolute(projectRoot));
    final target = _resolveContainedPath(root, normalized);
    if (!p.equals(root, target) && !p.isWithin(root, target)) {
      throw StateError('Path must stay within project root: $relativePath');
    }
    return target;
  }

  static String _resolveContainedPath(String root, String relativePath) {
    final normalized = ChangePlan.normalizeRelativePath(relativePath);
    final absoluteRoot = p.normalize(p.absolute(root));
    final target = p.normalize(
      p.joinAll([absoluteRoot, ...p.posix.split(normalized)]),
    );
    if (!p.equals(absoluteRoot, target) && !p.isWithin(absoluteRoot, target)) {
      throw StateError('Path must stay within owned root: $relativePath');
    }
    return target;
  }

  Future<List<_CommandEffect>> _validateCommands(ChangePlan plan) async {
    final effects = <_CommandEffect>[];
    for (final command in plan.commands) {
      final knownMutation = _isKnownMutation(command);
      if (knownMutation && !command.mutatesFiles) {
        throw StateError(
          'Known mutating command is marked non-mutating: '
          '${[command.executable, ...command.arguments].join(' ')}',
        );
      }
      if (!command.mutatesFiles) {
        effects.add(_CommandEffect.readOnly);
        continue;
      }

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
      } else if (command.executable == 'flutter' &&
          _startsWith(command.arguments, const ['pub', 'add'])) {
        _validatePubAdd(plan, command.arguments);
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
      effects.add(_CommandEffect.mutating);
    }
    return effects;
  }

  static bool _isKnownMutation(PlannedCommand command) {
    if (command.executable == 'dart') {
      return command.arguments.firstOrNull == 'format' ||
          _startsWith(command.arguments, const ['pub', 'get']) ||
          _startsWith(
            command.arguments,
            const ['run', 'build_runner', 'build'],
          );
    }
    return command.executable == 'flutter' &&
        (_startsWith(command.arguments, const ['pub', 'get']) ||
            _startsWith(command.arguments, const ['pub', 'add']));
  }

  static void _validateDartFormat(
    ChangePlan plan,
    List<String> arguments,
  ) {
    final targets = <String>[];
    for (final argument in arguments.skip(1)) {
      if (!argument.startsWith('-')) {
        targets.add(_normalizePositionalPath(argument));
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

  static void _validatePubAdd(ChangePlan plan, List<String> arguments) {
    if (arguments.length != 3 || arguments[2] != 'intl') {
      throw StateError(
        'Unsupported flutter pub add command: ${arguments.join(' ')}',
      );
    }
    _requireCoverage(plan, const ['pubspec.yaml', 'pubspec.lock']);
  }

  static void _requireCoverage(ChangePlan plan, Iterable<String> targets) {
    final uncovered = targets
        .map(ChangePlan.normalizeRelativePath)
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
    final portableTarget = ChangePlan.normalizeRelativePath(target);
    if (plan.files.any(
      (file) =>
          ChangePlan.normalizeRelativePath(file.relativePath) == portableTarget,
    )) {
      return true;
    }
    return plan.snapshotRoots.any((root) {
      final portableRoot = ChangePlan.normalizeRelativePath(root);
      final relative = p.posix.normalize(
        p.posix.relative(portableTarget, from: portableRoot),
      );
      return relative == '.' ||
          (relative != '..' && !relative.startsWith('../'));
    });
  }

  static String _normalizePositionalPath(String value) {
    try {
      return ChangePlan.normalizeRelativePath(value);
    } on ArgumentError {
      throw StateError('Mutating command has unsafe path argument: $value');
    }
  }

  static bool _hasUnsafeCommandCharacters(String value) {
    if (value.contains('\u0000') ||
        value.contains('\n') ||
        value.contains('\r') ||
        RegExp(r'''[%!^"';&|<>()`]''').hasMatch(value) ||
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

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

enum _CommandEffect { readOnly, mutating }

final class _Snapshot {
  const _Snapshot({
    required this.relativePath,
    required this.backupName,
    required this.existed,
    required this.isRoot,
  });

  final String relativePath;
  final String backupName;
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
