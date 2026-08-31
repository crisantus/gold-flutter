import 'package:gold_flutter/src/config/project_answers.dart';

final baseAnswers = ProjectAnswers.base(
  displayName: 'My Parking App',
  projectName: 'my_parking_app',
  applicationId: 'com.company.parking',
  platforms: TargetPlatform.values.toSet(),
);

final apiNoAuthAnswers = baseAnswers.copyWith(
  usesApi: true,
  apiBaseUri: Uri.parse('https://api.company.com'),
);

final apiAuthAnswers = apiNoAuthAnswers.copyWith(usesAuthentication: true);

final apiSampleAnswers = apiNoAuthAnswers.copyWith(includesSampleApi: true);

final authenticatedAnswers = apiAuthAnswers.copyWith(usesRefreshTokens: true);
