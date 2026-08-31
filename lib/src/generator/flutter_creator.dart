import 'dart:io';

import '../config/project_answers.dart';
import '../platform/app_identity.dart';
import '../process/process_executor.dart';
import 'project_generator.dart';

abstract interface class FlutterProjectCreator {
  Future<void> create({
    required ProjectAnswers answers,
    required Directory output,
  });
}

final class FlutterCreator implements FlutterProjectCreator {
  const FlutterCreator({required ProcessExecutor executor})
      : _executor = executor;

  final ProcessExecutor _executor;

  @override
  Future<void> create({
    required ProjectAnswers answers,
    required Directory output,
  }) async {
    final identity = AppIdentity(
      displayName: answers.displayName,
      projectName: answers.projectName,
      applicationId: answers.applicationId,
    );
    final platforms = answers.platforms.map((item) => item.name).toList()
      ..sort();
    final result = await _executor.run(
      'flutter',
      [
        'create',
        '--project-name',
        answers.projectName,
        '--org',
        identity.organization,
        '--platforms',
        platforms.join(','),
        '.',
      ],
      workingDirectory: output,
    );
    if (result.exitCode != 0) {
      throw ProjectGenerationException(
        result.stderr.trim().isEmpty
            ? 'flutter create failed with exit code ${result.exitCode}.'
            : result.stderr.trim(),
      );
    }
  }
}
