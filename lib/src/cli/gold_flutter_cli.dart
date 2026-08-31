import 'dart:io';

import 'package:args/args.dart';

import '../config/project_answers.dart';
import '../generator/project_generator.dart';
import '../process/process_executor.dart';
import '../prompts/answers_collector.dart';
import '../prompts/prompt_io.dart';
import '../validation/input_validation.dart';
import 'doctor_command.dart';

final class GoldFlutterCli {
  GoldFlutterCli({
    required PromptIO io,
    ProjectGenerator? generator,
    Directory? currentDirectory,
  })  : _io = io,
        _generator = generator ?? DefaultProjectGenerator.standard(),
        _currentDirectory = currentDirectory ?? Directory.current;

  static const version = '0.2.0-dev';

  final PromptIO _io;
  final ProjectGenerator _generator;
  final Directory _currentDirectory;

  Future<int> run(List<String> arguments) async {
    final parser = _buildParser();
    if (arguments.isNotEmpty &&
        arguments.first == 'create' &&
        arguments.any((argument) => argument == '--help' || argument == '-h')) {
      _io.writeLine('Usage: gold_flutter create [options]');
      _io.writeLine(parser.commands['create']!.usage);
      return 0;
    }
    late ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      _io.writeLine(error.message);
      _io.writeLine(parser.usage);
      return 64;
    }

    if (results['version'] as bool) {
      _io.writeLine('gold_flutter $version');
      return 0;
    }
    if (results['help'] as bool || arguments.isEmpty) {
      _writeHelp(parser);
      return 0;
    }

    final command = results.command;
    if (command == null) {
      _io.writeLine('Unknown command: ${arguments.first}');
      return 64;
    }

    switch (command.name) {
      case 'create':
        return _runCreate(command);
      case 'doctor':
        return _runDoctor();
      default:
        _io.writeLine('Unknown command: ${command.name}');
        return 64;
    }
  }

  Future<int> _runDoctor() async {
    final report = await DoctorCommand(
      executor: const LocalProcessExecutor(),
      workingDirectory: _currentDirectory,
    ).run();
    for (final check in report.checks) {
      _io.writeLine(
        '${check.isHealthy ? '✓' : '✗'} ${check.name}: ${check.detail}',
      );
    }
    return report.isHealthy ? 0 : 1;
  }

  Future<int> _runCreate(ArgResults command) async {
    try {
      final answers = command['yes'] as bool
          ? _answersFromFlags(command)
          : AnswersCollector(io: _io).collect();
      final outputDirectory = (command['output-directory'] as String?)?.trim();
      final destinationParent =
          outputDirectory == null || outputDirectory.isEmpty
              ? _currentDirectory
              : Directory(outputDirectory);
      _io.writeLine(
        'Creating ${answers.displayName}. This can take a few minutes...',
      );
      final output = await _generator.generate(
        answers: answers,
        destinationParent: destinationParent,
      );
      _io.writeLine('Created ${answers.displayName} at ${output.path}');
      return 0;
    } on UserCancelledException {
      _io.writeLine('Project creation cancelled.');
      return 0;
    } on FormatException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on ArgumentError catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on ProjectGenerationException catch (error) {
      _io.writeLine(error.message);
      return 1;
    } on Exception catch (error) {
      _io.writeLine('Project creation failed: $error');
      return 1;
    }
  }

  ProjectAnswers _answersFromFlags(ArgResults command) {
    final rawDisplayName = command['display-name'] as String?;
    if (rawDisplayName == null || rawDisplayName.trim().isEmpty) {
      throw const FormatException('--display-name is required with --yes.');
    }
    final displayName = InputValidation.displayName(rawDisplayName);
    final rawProjectName = (command['project-name'] as String?)?.trim();
    final projectName = InputValidation.projectName(
      rawProjectName == null || rawProjectName.isEmpty
          ? InputValidation.deriveProjectName(displayName)
          : rawProjectName,
    );
    final rawApplicationId = (command['application-id'] as String?)?.trim();
    final applicationId = InputValidation.applicationId(
      rawApplicationId == null || rawApplicationId.isEmpty
          ? 'com.example.$projectName'
          : rawApplicationId,
    );
    final defaultPlatforms =
        TargetPlatform.values.map((platform) => platform.name).join(',');
    final platforms = InputValidation.platforms(
      (command['platforms'] as String?) ?? defaultPlatforms,
    );
    final usesApi = command.wasParsed('api') ? command['api'] as bool : false;
    final rawApiBaseUrl = command['api-base-url'] as String?;
    if (usesApi && (rawApiBaseUrl == null || rawApiBaseUrl.trim().isEmpty)) {
      throw const FormatException(
        '--api-base-url is required when --api is enabled.',
      );
    }
    final apiBaseUri = usesApi ? InputValidation.httpUri(rawApiBaseUrl!) : null;
    final usesAuthentication =
        usesApi && (command.wasParsed('auth') ? command['auth'] as bool : true);
    final usesRefreshTokens = usesAuthentication &&
        (command.wasParsed('refresh-tokens')
            ? command['refresh-tokens'] as bool
            : true);
    final includesSampleApi = usesApi &&
        (command.wasParsed('sample-api')
            ? command['sample-api'] as bool
            : true);

    return ProjectAnswers(
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
  }

  ArgParser _buildParser() {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('version', negatable: false);
    parser.addCommand('create')
      ..addOption('display-name')
      ..addOption('project-name')
      ..addOption('application-id')
      ..addOption(
        'output-directory',
        help: 'Parent directory that will contain the generated project.',
      )
      ..addOption('platforms')
      ..addFlag('api', negatable: true)
      ..addOption('api-base-url')
      ..addFlag('auth', negatable: true)
      ..addFlag('refresh-tokens', negatable: true)
      ..addFlag('sample-api', negatable: true)
      ..addFlag('yes', abbr: 'y', negatable: false);
    parser.addCommand('doctor');
    return parser;
  }

  void _writeHelp(ArgParser parser) {
    _io.writeLine('Gold Flutter $version');
    _io.writeLine('Create a Riverpod + AutoRoute Flutter project.');
    _io.writeLine('');
    _io.writeLine('Usage: gold_flutter <create|doctor> [options]');
    _io.writeLine(parser.usage);
  }
}
