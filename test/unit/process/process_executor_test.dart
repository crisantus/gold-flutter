import 'dart:io';

import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:test/test.dart';

void main() {
  test('local executor captures exit code and output', () async {
    var started = false;
    final result = await const LocalProcessExecutor().run(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows
          ? const ['/c', 'echo', 'gold']
          : const ['-c', 'printf gold'],
      workingDirectory: Directory.current,
      onStarted: () {
        started = true;
      },
    );

    expect(started, isTrue);
    expect(result.exitCode, 0);
    expect(result.stdout.trim(), 'gold');
    expect(result.stderr, isEmpty);
  });
}
