import 'dart:io';

import 'package:gold_flutter/src/change/project_file_system.dart';
import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/cli/gold_flutter_cli.dart';
import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:gold_flutter/src/generator/project_generator.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:test/test.dart';

import '../../support/fake_process_executor.dart';
import '../../support/fake_prompt_io.dart';
import '../../support/project_fixture.dart';

void main() {
  test('--version prints the current generator version', () async {
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(io: io).run(['--version']);

    expect(exitCode, 0);
    expect(io.output.single, contains('0.2.0-dev'));
  });

  test('create flags build complete answers without prompting', () async {
    final generator = _FakeProjectGenerator();
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(
      io: io,
      generator: generator,
      currentDirectory: Directory('/work'),
    ).run([
      'create',
      '--display-name',
      'My App',
      '--project-name',
      'my_app',
      '--application-id',
      'com.company.myapp',
      '--platforms',
      'android,ios',
      '--api',
      '--api-base-url',
      'https://api.company.com',
      '--auth',
      '--refresh-tokens',
      '--sample-api',
      '--yes',
    ]);

    expect(exitCode, 0);
    expect(io.prompts, isEmpty);
    expect(generator.answers!.usesRefreshTokens, isTrue);
    expect(generator.destinationParent.path, '/work');
  });

  test('unknown commands return usage exit code 64', () async {
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(io: io).run(['unknown']);

    expect(exitCode, 64);
    expect(io.output.single, contains('Unknown command'));
  });

  test('create --help prints create options without prompting', () async {
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(io: io).run(['create', '--help']);

    expect(exitCode, 0);
    expect(io.prompts, isEmpty);
    expect(io.output.join('\n'), contains('--display-name'));
    expect(io.output.join('\n'), contains('--output-directory'));
  });

  test('arrange model --help lists every model arrangement option', () async {
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(io: io).run([
      'arrange',
      'model',
      '--help',
    ]);

    expect(exitCode, 0);
    expect(io.prompts, isEmpty);
    final output = io.output.join('\n');
    for (final option in [
      '--path',
      '--copy-with',
      '--test',
      '--dry-run',
      '--yes',
    ]) {
      expect(output, contains(option));
    }
  });

  test('arrange model without --path returns usage exit code 64', () async {
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(io: io).run([
      'arrange',
      'model',
      '--yes',
    ]);

    expect(exitCode, 64);
    expect(io.output.join('\n'), contains('--path is required'));
  });

  test('arrange model --dry-run previews without applying the transaction',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _supportedModel},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor(const {});
    final io = FakePromptIO(['yes']);

    final exitCode = await GoldFlutterCli(
      io: io,
      currentDirectory: fixture.root,
      changeTransaction: ChangeTransaction(executor: executor),
    ).run([
      'arrange',
      'model',
      '--path',
      'lib/domain/models/report_model.dart',
      '--dry-run',
    ]);

    expect(exitCode, 0);
    expect(executor.calls, isEmpty);
    expect(io.prompts, isEmpty);
    expect(io.output.join('\n'), contains('No files have been changed.'));
    expect(
      fixture.file('lib/domain/models/report_model.dart').readAsStringSync(),
      _supportedModel,
    );
  });

  test('arrange model --copy-with dry-run reports preserved copyWith and null',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _existingCopyWithModel},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor(const {});
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
      '--copy-with',
      '--dry-run',
    ]);

    expect(exitCode, 0);
    expect(executor.calls, isEmpty);
    expect(io.output, contains('Notice'));
    expect(
      io.output.join('\n'),
      contains('passing null preserves the current value and cannot clear it'),
    );
    expect(io.output, contains('Preserved'));
    expect(io.output.join('\n'), contains('ReportModel.copyWith'));
    expect(
      io.output.indexOf('Notice'),
      lessThan(io.output.indexOf('No files have been changed.')),
    );
  });

  test('arrange model apply reports a preserved non-owned test', () async {
    const existingTest = '// Maintained by the application team.\n';
    final fixture = await ProjectFixture.create(
      files: {
        'lib/domain/models/report_model.dart': _supportedModel,
        'test/domain/models/report_model_test.dart': existingTest,
      },
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor.success({
      'dart format lib/domain/models/report_model.dart': 'formatted',
      'flutter analyze': 'No issues found',
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
      '--copy-with',
      '--test',
      '--yes',
    ]);

    expect(exitCode, 0);
    expect(io.output, contains('Notice'));
    expect(io.output, contains('Preserved'));
    expect(
      io.output.join('\n'),
      contains('test/domain/models/report_model_test.dart'),
    );
    expect(
      fixture
          .file('test/domain/models/report_model_test.dart')
          .readAsStringSync(),
      existingTest,
    );
    expect(
      io.output.indexOf('Notice'),
      lessThan(io.output.indexWhere((line) => line.contains('formatted'))),
    );
  });

  test('arrange model aborts when its generated test appears before apply',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _supportedModel},
    );
    addTearDown(fixture.dispose);
    final testPath =
        fixture.file('test/domain/models/report_model_test.dart').path;
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
      changeTransaction: ChangeTransaction(
        executor: executor,
        fileSystem: _AppearingFileSystem(testPath),
      ),
    ).run([
      'arrange',
      'model',
      '--path',
      'lib/domain/models/report_model.dart',
      '--test',
      '--yes',
    ]);

    expect(exitCode, 1);
    expect(executor.calls, isEmpty);
    expect(
      io.output.join('\n'),
      contains('test/domain/models/report_model_test.dart'),
    );
    expect(
      fixture
          .file('test/domain/models/report_model_test.dart')
          .readAsStringSync(),
      'concurrent test content',
    );
  });

  test('arrange model returns 64 for an unsupported model', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _unsupportedModel},
    );
    addTearDown(fixture.dispose);
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(
      io: io,
      currentDirectory: fixture.root,
    ).run([
      'arrange',
      'model',
      '--path',
      'lib/domain/models/report_model.dart',
      '--yes',
    ]);

    expect(exitCode, 64);
    expect(io.output.join('\n'), contains('Unsupported field type'));
    expect(
      fixture.file('lib/domain/models/report_model.dart').readAsStringSync(),
      _unsupportedModel,
    );
  });

  test('arrange model returns 1 and restores input on verification failure',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _supportedModel},
    );
    addTearDown(fixture.dispose);
    final executor = FakeProcessExecutor({
      'dart format lib/domain/models/report_model.dart': const ProcessOutput(
        exitCode: 0,
        stdout: 'formatted',
        stderr: '',
      ),
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'fake analyzer failure',
      ),
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
      '--yes',
    ]);

    expect(exitCode, 1);
    expect(executor.calls, [
      'dart format lib/domain/models/report_model.dart',
      'flutter analyze',
    ]);
    expect(io.output.join('\n'), contains('fake analyzer failure'));
    expect(io.output.join('\n'), contains('Changes were restored.'));
    expect(
      fixture.file('lib/domain/models/report_model.dart').readAsStringSync(),
      _supportedModel,
    );
  });
}

final class _FakeProjectGenerator implements ProjectGenerator {
  ProjectAnswers? answers;
  late Directory destinationParent;

  @override
  Future<Directory> generate({
    required ProjectAnswers answers,
    required Directory destinationParent,
  }) async {
    this.answers = answers;
    this.destinationParent = destinationParent;
    return Directory('${destinationParent.path}/${answers.projectName}');
  }
}

final class _AppearingFileSystem implements ProjectFileSystem {
  _AppearingFileSystem(this.appearingPath);

  final String appearingPath;
  final ProjectFileSystem _delegate = const LocalProjectFileSystem();
  var _appearingPathChecks = 0;

  @override
  Future<String> createTemporaryDirectory(String prefix) =>
      _delegate.createTemporaryDirectory(prefix);

  @override
  Future<bool> exists(String path) async {
    if (path == appearingPath && ++_appearingPathChecks == 3) {
      final appearingFile = File(appearingPath);
      await appearingFile.parent.create(recursive: true);
      await appearingFile.writeAsString('concurrent test content');
    }
    return _delegate.exists(path);
  }

  @override
  Future<bool> isLink(String path) => _delegate.isLink(path);

  @override
  Future<bool> containsLink(String path) => _delegate.containsLink(path);

  @override
  Future<List<int>> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _delegate.writeBytes(path, bytes);

  @override
  Future<void> delete(String path) => _delegate.delete(path);

  @override
  Future<bool> deleteEmptyDirectory(String path) =>
      _delegate.deleteEmptyDirectory(path);

  @override
  Future<void> copyTree(String source, String destination) =>
      _delegate.copyTree(source, destination);
}

const _supportedModel = r'''class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );
}
''';

const _unsupportedModel = r'''class ReportModel {
  final Map<String, List<Object?>> grouped;

  ReportModel({required this.grouped});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        grouped: json?["grouped"] as Map<String, List<Object?>>,
      );
}
''';

const _existingCopyWithModel = r'''class ReportModel {
  final String? value;

  ReportModel({required this.value});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        value: (json?["value"] ?? "").toString(),
      );

  ReportModel copyWith({String? value}) {
    return ReportModel(value: value ?? this.value);
  }
}
''';
