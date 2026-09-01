import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/cli/gold_flutter_cli.dart';
import 'package:gold_flutter/src/optimize/project_optimizer.dart';
import 'package:test/test.dart';

import '../support/fake_process_executor.dart';
import '../support/fake_prompt_io.dart';
import '../support/project_fixture.dart';

void main() {
  test('optimize runs the exact detected project-health pipeline', () async {
    final fixture = await ProjectFixture.create(files: {
      'lib/main.dart': 'void main() {}\n',
      'test/widget_test.dart': '',
    });
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'flutter pub get': 'resolved',
      'dart format lib test': 'formatted',
      'flutter analyze': 'clean',
      'flutter test': 'passed',
    });
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(
      io: io,
      currentDirectory: fixture.root,
      projectOptimizer: ProjectOptimizer(
        transaction: ChangeTransaction(executor: executor),
      ),
    ).run(['optimize', '--yes']);

    expect(exitCode, 0);
    expect(executor.calls, [
      'flutter pub get',
      'dart format lib test',
      'flutter analyze',
      'flutter test',
    ]);
    expect(io.output.join('\n'), contains('Project health checks passed.'));
  });
}
