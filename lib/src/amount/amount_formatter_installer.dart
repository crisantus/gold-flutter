import 'dart:io';

import 'package:path/path.dart' as p;

import '../change/change_plan.dart';
import '../project/project_inspection.dart';
import 'amount_formatter_answers.dart';
import 'amount_formatter_renderer.dart';

final class AmountFormatterConflictException implements Exception {
  const AmountFormatterConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class AmountFormatterInstaller {
  const AmountFormatterInstaller({
    AmountFormatterRenderer renderer = const AmountFormatterRenderer(),
  }) : _renderer = renderer;

  static const ownershipMarker = AmountFormatterRenderer.ownershipMarker;
  static const sourcePath = 'lib/core/utils/money_formatter.dart';
  static const testPath = 'test/core/utils/money_formatter_test.dart';

  final AmountFormatterRenderer _renderer;

  Future<ChangePlan> plan(
    ProjectInspection project,
    AmountFormatterAnswers answers,
  ) async {
    final rendered = _renderer.render(answers, project.projectName);
    final files = <PlannedFileChange>[
      await _plannedFile(project, sourcePath, rendered.source),
      await _plannedFile(project, testPath, rendered.test),
    ];
    return ChangePlan(
      summary: 'Add amount formatter to ${project.projectName}',
      projectRoot: project.root,
      files: files,
      commands: [
        if (!project.dependencies.contains('intl'))
          PlannedCommand(
            executable: 'flutter',
            arguments: const ['pub', 'add', 'intl'],
            reason: 'Add the intl formatting dependency.',
            mutatesFiles: true,
          ),
        PlannedCommand(
          executable: 'dart',
          arguments: const ['format', sourcePath, testPath],
          reason: 'Format the generated formatter and test.',
          mutatesFiles: true,
        ),
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'Analyze the Flutter project.',
          mutatesFiles: false,
        ),
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['test', testPath],
          reason: 'Run the generated formatter test.',
          mutatesFiles: false,
        ),
      ],
      snapshotRoots: const ['pubspec.yaml', 'pubspec.lock'],
    );
  }

  Future<PlannedFileChange> _plannedFile(
    ProjectInspection project,
    String relativePath,
    String content,
  ) async {
    final file = File(p.join(project.root.path, relativePath));
    if (!await file.exists()) {
      return PlannedFileChange(
        relativePath: relativePath,
        content: content,
        kind: FileChangeKind.create,
        reason: 'Create a Gold Flutter-owned amount formatter file.',
        precondition: const TextFilePrecondition.absent(),
      );
    }
    final original = await file.readAsString();
    if (!original.startsWith('$ownershipMarker\n')) {
      throw AmountFormatterConflictException(
        'Refusing to overwrite unowned file: $relativePath',
      );
    }
    return PlannedFileChange(
      relativePath: relativePath,
      content: content,
      kind: FileChangeKind.modify,
      reason: 'Update the Gold Flutter-owned amount formatter file.',
      precondition: TextFilePrecondition.exact(original),
    );
  }
}
