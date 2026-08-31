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
  });

  test('API dependency set adds transport without token storage', () {
    final pubspec = const DependencyManifest().render(apiNoAuthAnswers);

    expect(pubspec, contains('dio:'));
    expect(pubspec, contains('dartz:'));
    expect(pubspec, contains('internet_connection_checker_plus:'));
    expect(pubspec, isNot(contains('flutter_secure_storage:')));
  });

  test('authenticated dependency set adds secure storage', () {
    final pubspec = const DependencyManifest().render(authenticatedAnswers);

    expect(pubspec, contains('flutter_secure_storage:'));
  });
}
