import 'dart:io';

import 'package:gold_flutter/src/process/process_executor.dart';

final class FakeProcessExecutor implements ProcessExecutor {
  FakeProcessExecutor(this.outputs);

  final Map<String, ProcessOutput> outputs;
  final List<String> calls = [];

  factory FakeProcessExecutor.success(Map<String, String> stdoutByCommand) {
    return FakeProcessExecutor({
      for (final entry in stdoutByCommand.entries)
        entry.key: ProcessOutput(
          exitCode: 0,
          stdout: entry.value,
          stderr: '',
        ),
    });
  }

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) async {
    final command = [executable, ...arguments].join(' ');
    calls.add(command);
    onStarted?.call();
    return outputs[command] ??
        const ProcessOutput(
          exitCode: 127,
          stdout: '',
          stderr: 'Command not found',
        );
  }
}
