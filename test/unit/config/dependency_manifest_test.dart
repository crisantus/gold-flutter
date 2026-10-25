import 'package:gold_flutter/src/config/dependency_manifest.dart';
import 'package:test/test.dart';

import '../../support/project_answers_fixtures.dart';

void main() {
  test('base dependency set keeps networking packages out', () {
    final pubspec = const DependencyManifest().render(baseAnswers);

    expect(pubspec, contains('flutter_riverpod:'));
    expect(pubspec, contains('auto_route:'));
    expect(pubspec, isNot(contains('dio:')));
    expect(pubspec, isNot(contains('flutter_secure_storage:')));
    expect(pubspec, isNot(contains('shared_preferences:')));
  });

  test('API dependency set adds transport without token storage', () {
    final pubspec = const DependencyManifest().render(apiNoAuthAnswers);

    expect(pubspec, contains('dio:'));
    expect(pubspec, contains('dartz:'));
    expect(pubspec, contains('internet_connection_checker_plus:'));
    expect(pubspec, isNot(contains('flutter_secure_storage:')));
    expect(pubspec, isNot(contains('shared_preferences:')));
  });

  for (final answers in [apiAuthAnswers, authenticatedAnswers]) {
    test(
        'authenticated dependencies use preferences '
        '(refresh: ${answers.usesRefreshTokens})', () {
      final pubspec = const DependencyManifest().render(answers);

      expect(pubspec, contains('shared_preferences: ^2.3.5'));
      expect(pubspec, isNot(contains('flutter_secure_storage:')));
    });
  }
}
