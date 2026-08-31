import 'dart:io';

import '../process/process_executor.dart';
import 'project_generator.dart';

abstract interface class ProjectVerifier {
  Future<void> verify(Directory projectRoot);
}

final class GeneratedProjectVerifier implements ProjectVerifier {
  const GeneratedProjectVerifier({required ProcessExecutor executor})
      : _executor = executor;

  final ProcessExecutor _executor;

  @override
  Future<void> verify(Directory projectRoot) async {
    await _run(projectRoot, 'flutter', const ['pub', 'get']);
    await _run(projectRoot, 'dart', const [
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs',
    ]);
    await _run(projectRoot, 'dart', const ['format', 'lib', 'test']);
    await _run(projectRoot, 'flutter', const ['analyze']);
    await _run(projectRoot, 'flutter', const ['test']);
  }

  Future<void> _run(
    Directory workingDirectory,
    String executable,
    List<String> arguments,
  ) async {
    final output = await _executor.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (output.exitCode == 0) return;
    final detail = [
      output.stdout.trim(),
      output.stderr.trim(),
    ].where((value) => value.isNotEmpty).join('\n');
    throw ProjectGenerationException(
      '${[executable, ...arguments].join(' ')} failed'
      '${detail.isEmpty ? '.' : ': $detail'}',
    );
  }
}
