import 'dart:io';

import 'package:gold_flutter/src/generator/flutter_creator.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:test/test.dart';

import '../../support/project_answers_fixtures.dart';

void main() {
  test('invokes flutter create with selected platforms and derived org',
      () async {
    final executor = _RecordingProcessExecutor();
    final creator = FlutterCreator(executor: executor);

    await creator.create(
      answers: authenticatedAnswers.copyWith(
        applicationId: 'com.company.parking',
        platforms: {
          ...authenticatedAnswers.platforms.where(
            (platform) => platform.name == 'android' || platform.name == 'ios',
          ),
        },
      ),
      output: Directory('/tmp/staging'),
    );

    expect(executor.executable, 'flutter');
    expect(executor.arguments, [
      'create',
      '--project-name',
      'my_parking_app',
      '--org',
      'com.company',
      '--platforms',
      'android,ios',
      '.',
    ]);
  });
}

final class _RecordingProcessExecutor implements ProcessExecutor {
  late String executable;
  late List<String> arguments;

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    return const ProcessOutput(exitCode: 0, stdout: '', stderr: '');
  }
}
