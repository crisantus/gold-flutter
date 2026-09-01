import '../config/project_answers.dart';
import '../validation/input_validation.dart';
import 'multi_select_prompt.dart';
import 'prompt_io.dart';

export 'prompt_io.dart' show UserCancelledException;

final class AnswersCollector {
  const AnswersCollector({required PromptIO io}) : _io = io;

  final PromptIO _io;

  ProjectAnswers collect() {
    final displayName = _validated(
      'Project display name: ',
      InputValidation.displayName,
    );
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
    final platforms = _collectPlatforms();
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

  Set<TargetPlatform> _collectPlatforms() {
    final options = TargetPlatform.values
        .map(
          (platform) => MultiSelectOption(
            value: platform.name,
            label: _platformLabel(platform),
          ),
        )
        .toList(growable: false);
    if (_io case final MultiSelectPromptIO interactiveIO) {
      final selected = interactiveIO.selectMany(
        title: 'Select target platforms',
        options: options,
        initiallySelected:
            TargetPlatform.values.map((platform) => platform.name).toSet(),
      );
      if (selected != null) {
        return InputValidation.platforms(selected.join(','));
      }
    }

    _io.writeLine('Select target platforms by number or name:');
    for (var index = 0; index < options.length; index++) {
      _io.writeLine('  ${index + 1}. ${options[index].label}');
    }
    return _validatedWithDefault(
      'Platforms [all]: ',
      'all',
      InputValidation.platforms,
    );
  }

  String _platformLabel(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android => 'Android',
        TargetPlatform.ios => 'iOS',
        TargetPlatform.web => 'Web',
        TargetPlatform.macos => 'macOS',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
      };

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
