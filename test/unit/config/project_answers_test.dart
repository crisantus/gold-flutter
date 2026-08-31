import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:test/test.dart';

void main() {
  test('API projects require an HTTP base URI', () {
    expect(
      () => ProjectAnswers(
        displayName: 'Parking',
        projectName: 'parking',
        applicationId: 'com.company.parking',
        platforms: TargetPlatform.values.toSet(),
        usesApi: true,
        apiBaseUri: null,
        usesAuthentication: false,
        usesRefreshTokens: false,
        includesSampleApi: true,
      ),
      throwsArgumentError,
    );
  });

  test('base answers disable every API-only choice', () {
    final answers = ProjectAnswers.base(
      displayName: 'Parking',
      projectName: 'parking',
      applicationId: 'com.company.parking',
      platforms: TargetPlatform.values.toSet(),
    );

    expect(answers.usesApi, isFalse);
    expect(answers.apiBaseUri, isNull);
    expect(answers.usesAuthentication, isFalse);
    expect(answers.usesRefreshTokens, isFalse);
    expect(answers.includesSampleApi, isFalse);
  });

  test('refresh tokens require authentication', () {
    expect(
      () => ProjectAnswers(
        displayName: 'Parking',
        projectName: 'parking',
        applicationId: 'com.company.parking',
        platforms: TargetPlatform.values.toSet(),
        usesApi: true,
        apiBaseUri: Uri.parse('https://api.example.com'),
        usesAuthentication: false,
        usesRefreshTokens: true,
        includesSampleApi: false,
      ),
      throwsArgumentError,
    );
  });

  test('platform choices are immutable', () {
    final platforms = {TargetPlatform.android};
    final answers = ProjectAnswers.base(
      displayName: 'Parking',
      projectName: 'parking',
      applicationId: 'com.company.parking',
      platforms: platforms,
    );
    platforms.add(TargetPlatform.ios);

    expect(answers.platforms, {TargetPlatform.android});
    expect(
      () => answers.platforms.add(TargetPlatform.web),
      throwsUnsupportedError,
    );
  });
}
