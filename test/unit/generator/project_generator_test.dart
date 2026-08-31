import 'dart:io';

import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:gold_flutter/src/generator/flutter_creator.dart';
import 'package:gold_flutter/src/generator/project_generator.dart';
import 'package:gold_flutter/src/generator/project_verifier.dart';
import 'package:gold_flutter/src/generator/template_renderer.dart';
import 'package:gold_flutter/src/platform/app_identity.dart';
import 'package:gold_flutter/src/platform/platform_patcher.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/project_answers_fixtures.dart';

void main() {
  test('publishes only after every generation stage succeeds', () async {
    final parent = await Directory.systemTemp.createTemp('gold_project_test_');
    addTearDown(() => parent.delete(recursive: true));
    final calls = <String>[];
    final generator = DefaultProjectGenerator(
      creator: _FakeCreator(calls),
      platformPatcher: _FakePlatformPatcher(calls),
      renderer: _FakeRenderer(calls),
      verifier: _FakeVerifier(calls),
    );

    final output = await generator.generate(
      answers: baseAnswers,
      destinationParent: parent,
    );

    expect(calls, ['create', 'identity', 'render', 'verify']);
    expect(output.path, p.join(parent.path, baseAnswers.projectName));
    expect(File(p.join(output.path, 'ready.txt')).readAsStringSync(), 'ready');
  });

  test('a failed verification leaves no destination or staging directory',
      () async {
    final parent = await Directory.systemTemp.createTemp('gold_project_test_');
    addTearDown(() => parent.delete(recursive: true));
    final calls = <String>[];
    final generator = DefaultProjectGenerator(
      creator: _FakeCreator(calls),
      platformPatcher: _FakePlatformPatcher(calls),
      renderer: _FakeRenderer(calls),
      verifier: _FakeVerifier(calls, shouldFail: true),
    );

    await expectLater(
      generator.generate(answers: baseAnswers, destinationParent: parent),
      throwsA(isA<ProjectGenerationException>()),
    );

    expect(Directory(p.join(parent.path, baseAnswers.projectName)).existsSync(),
        isFalse);
    expect(
      parent.listSync().where(
            (entry) => p.basename(entry.path).startsWith('.gold_flutter_'),
          ),
      isEmpty,
    );
  });
}

final class _FakeCreator implements FlutterProjectCreator {
  _FakeCreator(this.calls);
  final List<String> calls;

  @override
  Future<void> create({
    required ProjectAnswers answers,
    required Directory output,
  }) async {
    calls.add('create');
  }
}

final class _FakePlatformPatcher implements ProjectPlatformPatcher {
  _FakePlatformPatcher(this.calls);
  final List<String> calls;

  @override
  Future<void> apply({
    required Directory projectRoot,
    required AppIdentity identity,
  }) async {
    calls.add('identity');
  }
}

final class _FakeRenderer implements ProjectTemplateRenderer {
  _FakeRenderer(this.calls);
  final List<String> calls;

  @override
  Future<void> render({
    required Directory projectRoot,
    required ProjectAnswers answers,
  }) async {
    calls.add('render');
    await File(p.join(projectRoot.path, 'ready.txt')).writeAsString('ready');
  }
}

final class _FakeVerifier implements ProjectVerifier {
  _FakeVerifier(this.calls, {this.shouldFail = false});
  final List<String> calls;
  final bool shouldFail;

  @override
  Future<void> verify(Directory projectRoot) async {
    calls.add('verify');
    if (shouldFail) {
      throw const ProjectGenerationException('verification failed');
    }
  }
}
