import 'dart:io';

import 'package:gold_flutter/src/generator/project_generator.dart';
import 'package:gold_flutter/src/generator/project_verifier.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:test/test.dart';

void main() {
  test('failed commands preserve both diagnostic output streams', () async {
    final verifier = GeneratedProjectVerifier(
      executor: _FailingExecutor(),
    );

    await expectLater(
      verifier.verify(Directory('/tmp/project')),
      throwsA(
        isA<ProjectGenerationException>()
            .having(
                (error) => error.message, 'message', contains('detail line'))
            .having(
                (error) => error.message, 'message', contains('summary line')),
      ),
    );
  });
}

final class _FailingExecutor implements ProcessExecutor {
  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    return const ProcessOutput(
      exitCode: 1,
      stdout: 'detail line',
      stderr: 'summary line',
    );
  }
}
