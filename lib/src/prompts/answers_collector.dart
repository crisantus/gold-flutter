import '../config/project_answers.dart';
import '../validation/input_validation.dart';
import 'prompt_io.dart';

final class UserCancelledException implements Exception {
  const UserCancelledException();
}

final class AnswersCollector {
  const AnswersCollector({required PromptIO io}) : _io = io;

  final PromptIO _io;

  ProjectAnswers collect() {
    final displayName = _required('Project display name: ');
    final derivedName = InputValidation.deriveProjectName(displayName);
    final projectName = _validatedWithDefault(
      'Dart project name [$derivedName]: ',
      derivedName,
      InputValidation.projectName,
    );
    final defaultApplicationId = 'com.example.$projectName';
    final applicationId = _validatedWithDefault(
      'Package/application ID [$defaultApplicationId]: ',
      defaultApplicationId,
      InputValidation.applicationId,
    );
    final defaultPlatforms =
        TargetPlatform.values.map((platform) => platform.name).join(',');
    final platforms = _validatedWithDefault(
      'Platforms [$defaultPlatforms]: ',
      defaultPlatforms,
      InputValidation.platforms,
    );
    final usesApi = _yesNo('Does this app consume APIs? [y/N]: ', false);

    Uri? apiBaseUri;
    var usesAuthentication = false;
    var usesRefreshTokens = false;
    var includesSampleApi = false;
    if (usesApi) {
      apiBaseUri = _validated('API base URL: ', InputValidation.httpUri);
      usesAuthentication = _yesNo(
        'Will users sign in to protected API endpoints? [Y/n]: ',
        true,
      );
      if (usesAuthentication) {
        usesRefreshTokens = _yesNo(
          'Does the backend issue refresh tokens? [Y/n]: ',
          true,
        );
      }
      includesSampleApi = _yesNo(
        'Generate a complete sample API feature? [Y/n]: ',
        true,
      );
    }

    final answers = ProjectAnswers(
      displayName: displayName,
      projectName: projectName,
      applicationId: applicationId,
      platforms: platforms,
      usesApi: usesApi,
      apiBaseUri: apiBaseUri,
      usesAuthentication: usesAuthentication,
      usesRefreshTokens: usesRefreshTokens,
      includesSampleApi: includesSampleApi,
    );
    _writeSummary(answers);
    if (!_yesNo('Create project now? [Y/n]: ', true)) {
      throw const UserCancelledException();
    }
    return answers;
  }

  String _required(String prompt) {
    while (true) {
      _io.write(prompt);
      final value = _read().trim();
      if (value.isNotEmpty) return value;
      _io.writeLine('A value is required.');
    }
  }

  T _validated<T>(String prompt, T Function(String) validator) {
    while (true) {
      _io.write(prompt);
      try {
        return validator(_read());
      } on FormatException catch (error) {
        _io.writeLine(error.message);
      }
    }
  }

  T _validatedWithDefault<T>(
    String prompt,
    String defaultValue,
    T Function(String) validator,
  ) {
    while (true) {
      _io.write(prompt);
      final value = _read().trim();
      try {
        return validator(value.isEmpty ? defaultValue : value);
      } on FormatException catch (error) {
        _io.writeLine(error.message);
      }
    }
  }

  bool _yesNo(String prompt, bool defaultValue) {
    while (true) {
      _io.write(prompt);
      switch (_read().trim().toLowerCase()) {
        case '':
          return defaultValue;
        case 'y':
        case 'yes':
          return true;
        case 'n':
        case 'no':
          return false;
        default:
          _io.writeLine('Enter yes or no.');
      }
    }
  }

  String _read() {
    final value = _io.readLine();
    if (value == null) {
      throw const FormatException('Input ended before setup was complete.');
    }
    return value;
  }

  void _writeSummary(ProjectAnswers answers) {
    _io.writeLine('');
    _io.writeLine('Project summary');
    _io.writeLine('  Display name: ${answers.displayName}');
    _io.writeLine('  Project name: ${answers.projectName}');
    _io.writeLine('  Package ID: ${answers.applicationId}');
    _io.writeLine(
      '  Platforms: ${answers.platforms.map((item) => item.name).join(', ')}',
    );
    _io.writeLine('  API support: ${answers.usesApi ? 'yes' : 'no'}');
    if (answers.usesApi) {
      _io.writeLine('  API base URL: ${answers.apiBaseUri}');
      _io.writeLine(
        '  Protected sign-in: ${answers.usesAuthentication ? 'yes' : 'no'}',
      );
      _io.writeLine(
        '  Refresh tokens: ${answers.usesRefreshTokens ? 'yes' : 'no'}',
      );
      _io.writeLine(
        '  Sample API feature: ${answers.includesSampleApi ? 'yes' : 'no'}',
      );
    }
    _io.writeLine('');
  }
}
