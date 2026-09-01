import 'dart:io';

final class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class ProcessExecutor {
  /// Calls [onStarted] exactly once after the subprocess has started.
  ///
  /// Implementations must not call it when process spawning fails.
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  });
}

final class LocalProcessExecutor implements ProcessExecutor {
  const LocalProcessExecutor();

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      runInShell: Platform.isWindows,
    );
    onStarted?.call();
    final stdinClosed = process.stdin.close();
    final stdout = process.stdout.transform(systemEncoding.decoder).join();
    final stderr = process.stderr.transform(systemEncoding.decoder).join();
    await stdinClosed;
    final exitCode = await process.exitCode;
    return ProcessOutput(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  }
}
