import 'dart:io';

import 'package:gold_flutter/src/cli/gold_flutter_cli.dart';
import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:gold_flutter/src/generator/project_generator.dart';
import 'package:test/test.dart';

import '../../support/fake_prompt_io.dart';

void main() {
  test('--version prints the current generator version', () async {
    final io = FakePromptIO([]);

    final exitCode = await GoldFlutterCli(io: io).run(['--version']);

    expect(exitCode, 0);
    expect(io.output.single, contains('0.1.0'));
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
