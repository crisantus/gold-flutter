import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:gold_flutter/src/validation/input_validation.dart';
import 'package:test/test.dart';

void main() {
  group('project names', () {
    test('derives valid snake_case from a display name', () {
      expect(
        InputValidation.deriveProjectName('My Parking App'),
        'my_parking_app',
      );
      expect(
          InputValidation.deriveProjectName('2026 Launch'), 'app_2026_launch');
    });

    test('validates Dart package syntax', () {
      expect(() => InputValidation.projectName('my_app'), returnsNormally);
      expect(
        () => InputValidation.projectName('My App'),
        throwsFormatException,
      );
      expect(
        () => InputValidation.deriveProjectName('---'),
        throwsFormatException,
      );
    });
  });

  test('requires a reverse-domain application id with three segments', () {
    expect(
      () => InputValidation.applicationId('com.company.parking'),
      returnsNormally,
    );
    expect(
      () => InputValidation.applicationId('parking'),
      throwsFormatException,
    );
    expect(
      () => InputValidation.applicationId('com.Company.parking'),
      throwsFormatException,
    );
  });

  test('requires an HTTP or HTTPS base URL with a host', () {
    expect(
      InputValidation.httpUri('https://api.company.com/v1'),
      Uri.parse('https://api.company.com/v1'),
    );
    expect(
      () => InputValidation.httpUri('ftp://api.company.com'),
      throwsFormatException,
    );
    expect(() => InputValidation.httpUri('/v1'), throwsFormatException);
  });

  test('parses target platforms and rejects empty or unknown choices', () {
    expect(InputValidation.platforms('android, ios'), {
      TargetPlatform.android,
      TargetPlatform.ios,
    });
    expect(() => InputValidation.platforms(''), throwsFormatException);
    expect(
      () => InputValidation.platforms('android,fuchsia'),
      throwsFormatException,
    );
  });
}
