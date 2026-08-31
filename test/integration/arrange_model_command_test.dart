import 'dart:io';

import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/cli/gold_flutter_cli.dart';
import 'package:gold_flutter/src/model/model_test_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_process_executor.dart';
import '../support/fake_prompt_io.dart';
import '../support/project_fixture.dart';

void main() {
  test('arrange model applies the EyeAsk golden and creates an owned test',
      () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final repositoryRoot = Directory.current.path;
    final source = File(
      p.join(repositoryRoot, 'test/fixtures/models/eyeask_input.dart'),
    );
    final golden = File(
      p.join(repositoryRoot, 'test/fixtures/models/eyeask_expected.dart'),
    );
    final model = fixture.file('lib/domain/models/report_model.dart');
    await model.parent.create(recursive: true);
    await source.copy(model.path);
    final executor = FakeProcessExecutor.success({
      'dart format lib/domain/models/report_model.dart '
          'test/domain/models/report_model_test.dart': 'formatted',
      'flutter analyze': 'No issues found',
      'flutter test test/domain/models/report_model_test.dart': 'passed',
    });
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(
      io: io,
      currentDirectory: fixture.root,
      changeTransaction: ChangeTransaction(executor: executor),
    ).run([
      'arrange',
      'model',
      '--path',
      'lib/domain/models/report_model.dart',
      '--test',
      '--yes',
    ]);

    expect(exitCode, 0);
    expect(await model.readAsString(), await golden.readAsString());
    final ownedTest = fixture.file('test/domain/models/report_model_test.dart');
    expect(await ownedTest.exists(), isTrue);
    expect(
      (await ownedTest.readAsLines()).first,
      ModelTestRenderer.ownershipMarker,
    );
    expect(executor.calls, [
      'dart format lib/domain/models/report_model.dart '
          'test/domain/models/report_model_test.dart',
      'flutter analyze',
      'flutter test test/domain/models/report_model_test.dart',
    ]);
  });
}
