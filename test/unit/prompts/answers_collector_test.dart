import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:gold_flutter/src/prompts/answers_collector.dart';
import 'package:test/test.dart';

import '../../support/fake_prompt_io.dart';

void main() {
  test('no-API flow skips API and authentication questions', () {
    final io = FakePromptIO([
      'My Parking App',
      '',
      'com.company.parking',
      '',
      'n',
      'y',
    ]);

    final answers = AnswersCollector(io: io).collect();

    expect(answers.projectName, 'my_parking_app');
    expect(answers.platforms, TargetPlatform.values.toSet());
    expect(answers.usesApi, isFalse);
    expect(io.prompts.join(), isNot(contains('protected API endpoints')));
  });

  test('authenticated API flow collects refresh and sample choices', () {
    final io = FakePromptIO([
      'My Parking App',
      '',
      'com.company.parking',
      'android,ios',
      'y',
      'https://api.company.com',
      '',
      'n',
      '',
      'y',
    ]);

    final answers = AnswersCollector(io: io).collect();

    expect(answers.usesAuthentication, isTrue);
    expect(answers.usesRefreshTokens, isFalse);
    expect(answers.includesSampleApi, isTrue);
  });

  test('invalid input explains the rule and asks again', () {
    final io = FakePromptIO([
      'My App',
      'My App',
      '',
      'invalid',
      'com.company.myapp',
      '',
      'n',
      'y',
    ]);

    final answers = AnswersCollector(io: io).collect();

    expect(answers.projectName, 'my_app');
    expect(io.output, contains(contains('snake_case')));
    expect(io.output, contains(contains('reverse-domain')));
  });

  test('declining the final summary cancels safely', () {
    final io = FakePromptIO(['My App', '', '', '', 'n', 'n']);

    expect(
      () => AnswersCollector(io: io).collect(),
      throwsA(isA<UserCancelledException>()),
    );
  });
}
