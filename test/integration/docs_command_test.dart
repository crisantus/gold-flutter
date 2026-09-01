import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/cli/gold_flutter_cli.dart';
import 'package:test/test.dart';

import '../support/fake_process_executor.dart';
import '../support/fake_prompt_io.dart';
import '../support/project_fixture.dart';

void main() {
  test('generates owned docs repeatedly while preserving a user edit',
      () async {
    final fixture = await ProjectFixture.create(files: {
      'lib/main.dart': 'void main() {}\n',
      'lib/domain/models/user_model.dart':
          'class UserModel { final String id; UserModel(this.id); }\n',
    });
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'flutter analyze': 'clean',
    });

    Future<int> run() => GoldFlutterCli(
          io: FakePromptIO([]),
          currentDirectory: fixture.root,
          changeTransaction: ChangeTransaction(executor: executor),
        ).run(['docs', '--yes']);

    expect(await run(), 0);
    expect(await run(), 0);
    final models = fixture.file('docs/gold_flutter/models.md');
    await models.writeAsString('user-owned model notes');
    expect(await run(), 0);

    expect(await models.readAsString(), 'user-owned model notes');
    expect(await fixture.file('docs/gold_flutter/README.md').exists(), isTrue);
    expect(
      await fixture.file('docs/gold_flutter/.gold_flutter_docs.json').exists(),
      isTrue,
    );
    expect(executor.calls,
        ['flutter analyze', 'flutter analyze', 'flutter analyze']);
  });
}
