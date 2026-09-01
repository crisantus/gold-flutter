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

  test(
    'local executor closes child stdin so an EOF reader completes',
    () async {
      final root = await Directory.systemTemp.createTemp('gold_process_eof_');
      addTearDown(() => root.delete(recursive: true));
      final child = File('${root.path}${Platform.pathSeparator}child.dart');
      await child.writeAsString('''
import 'dart:io';

Future<void> main() async {
  await stdin.drain<void>();
  stdout.write('stdout after eof');
  stderr.write('stderr after eof');
  await stdout.flush();
  await stderr.flush();
  exitCode = 23;
}
''');
      var started = false;

      final result = await const LocalProcessExecutor().run(
        Platform.resolvedExecutable,
        [child.path],
        workingDirectory: root,
        onStarted: () {
          started = true;
        },
      ).timeout(const Duration(seconds: 5));

      expect(started, isTrue);
      expect(result.exitCode, 23);
      expect(result.stdout, 'stdout after eof');
      expect(result.stderr, 'stderr after eof');
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
