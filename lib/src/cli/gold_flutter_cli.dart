import 'dart:io';

import 'package:args/args.dart';

import '../amount/amount_formatter_answers.dart';
import '../amount/amount_formatter_answers_collector.dart';
import '../amount/amount_formatter_installer.dart';
import '../change/change_plan_presenter.dart';
import '../change/change_report.dart';
import '../change/change_transaction.dart';
import '../config/project_answers.dart';
import '../docs/documentation_generator.dart';
import '../generator/project_generator.dart';
import '../model/model_arranger.dart';
import '../optimize/project_auditor.dart';
import '../optimize/project_optimizer.dart';
import '../process/process_executor.dart';
import '../project/project_inspector.dart';
import '../prompts/answers_collector.dart';
import '../prompts/prompt_io.dart';
import '../validation/input_validation.dart';
import 'doctor_command.dart';

final class GoldFlutterCli {
  GoldFlutterCli({
    required PromptIO io,
    ProjectGenerator? generator,
    Directory? currentDirectory,
    ModelArranger? modelArranger,
    ChangeTransaction? changeTransaction,
    ProjectOptimizer? projectOptimizer,
  })  : _io = io,
        _generator = generator ?? DefaultProjectGenerator.standard(),
        _currentDirectory = currentDirectory ?? Directory.current,
        _modelArranger = modelArranger ?? const ModelArranger(),
        _changeTransaction = changeTransaction ??
            ChangeTransaction(executor: const LocalProcessExecutor()),
        _projectOptimizer = projectOptimizer ?? const ProjectOptimizer();

  static const version = '0.2.0-dev';

  final PromptIO _io;
  final ProjectGenerator _generator;
  final Directory _currentDirectory;
  final ModelArranger _modelArranger;
  final ChangeTransaction _changeTransaction;
  final ProjectOptimizer _projectOptimizer;

  Future<int> run(List<String> arguments) async {
    final parser = _buildParser();
    if (arguments.isEmpty) {
      _writeHelp();
      return 0;
    }
    if (arguments.first == 'help') {
      return _writeCommandHelp(parser, arguments.skip(1).toList());
    }
    if (arguments.any((argument) => argument == '--help' || argument == '-h')) {
      final path = arguments
          .takeWhile((argument) => argument != '--help' && argument != '-h')
          .takeWhile((argument) => !argument.startsWith('-'))
          .toList();
      return _writeCommandHelp(parser, path);
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
    if (results['help'] as bool) {
      _writeHelp();
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
      case 'arrange':
        return _runArrange(command);
      case 'optimize':
        return _runOptimize(command);
      case 'add':
        return _runAdd(command);
      case 'docs':
        return _runDocs(command);
      default:
        _io.writeLine('Unknown command: ${command.name}');
        return 64;
    }
  }

  Future<int> _runDocs(ArgResults command) async {
    try {
      final project = await const ProjectInspector().inspect(_currentDirectory);
      if (project.isDirty) {
        _io.writeLine('Warning: the project has uncommitted Git changes.');
      }
      final plan = await const DocumentationGenerator().plan(project);
      final presenter = ChangePlanPresenter(io: _io)..print(plan);
      final apply = presenter.confirm(
        assumeYes: command['yes'] as bool,
        dryRun: command['dry-run'] as bool,
      );
      if (!apply) return 0;

      final report = await _changeTransaction.execute(plan);
      final output = report.output.trimRight();
      if (output.isNotEmpty) _io.writeLine(output);
      if (!report.success) {
        _io.writeLine('Documentation generation failed.');
        _io.writeLine(
          report.restored
              ? 'Restoration status: completed. Changes were restored.'
              : 'Restoration status: incomplete or not required; inspect '
                  'docs/gold_flutter before retrying.',
        );
        return 1;
      }
      presenter.printReport(report, preserved: plan.preserved);
      _io.writeLine('Project documentation generated.');
      return 0;
    } on ProjectInspectionException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on FormatException catch (error) {
      _io.writeLine(error.message);
      return 1;
    } on Exception catch (error) {
      _io.writeLine('Documentation generation failed: $error');
      return 1;
    }
  }

  Future<int> _runAdd(ArgResults command) async {
    final nested = command.command;
    if (nested == null || nested.name != 'amount-formatter') {
      _io.writeLine('Usage: gold_flutter add amount-formatter [options]');
      return 64;
    }
    return _runAddAmountFormatter(nested);
  }

  Future<int> _runAddAmountFormatter(ArgResults command) async {
    try {
      final answers = command['yes'] as bool
          ? _amountAnswersFromFlags(command)
          : AmountFormatterAnswersCollector(io: _io).collect();
      final project = await const ProjectInspector().inspect(_currentDirectory);
      if (project.isDirty) {
        _io.writeLine('Warning: the project has uncommitted Git changes.');
      }
      final plan =
          await const AmountFormatterInstaller().plan(project, answers);
      final presenter = ChangePlanPresenter(io: _io)..print(plan);
      final apply = presenter.confirm(
        assumeYes: command['yes'] as bool,
        dryRun: command['dry-run'] as bool,
      );
      if (!apply) {
        return 0;
      }
      final report = await _changeTransaction.execute(plan);
      final output = report.output.trimRight();
      if (output.isNotEmpty) {
        _io.writeLine(output);
      }
      if (!report.success) {
        _io.writeLine('Amount formatter installation failed.');
        _io.writeLine(
          report.restored
              ? 'Restoration status: completed. Changes were restored.'
              : 'Restoration status: incomplete or not required; inspect the '
                  'planned files before retrying.',
        );
        return 1;
      }
      presenter.printReport(report, preserved: plan.preserved);
      _io.writeLine('Amount formatter installed.');
      return 0;
    } on AmountFormatterConflictException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on ProjectInspectionException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on FormatException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on ArgumentError catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on Exception catch (error) {
      _io.writeLine('Amount formatter installation failed: $error');
      return 1;
    }
  }

  AmountFormatterAnswers _amountAnswersFromFlags(ArgResults command) {
    final digitsText = command['decimal-digits'] as String;
    final digits = int.tryParse(digitsText);
    if (digits == null) {
      throw const FormatException('--decimal-digits must be an integer.');
    }
    return AmountFormatterAnswers(
      locale: command['locale'] as String,
      symbol: command['symbol'] as String,
      decimalDigits: digits,
      useGrouping: command['grouping'] as bool,
      hiddenText: command['hidden-text'] as String,
    );
  }

  Future<int> _runOptimize(ArgResults command) async {
    try {
      final project = await const ProjectInspector().inspect(_currentDirectory);
      if (project.isDirty) {
        _io.writeLine('Warning: the project has uncommitted Git changes.');
      }
      final plan = await _projectOptimizer.plan(project);
      final presenter = ChangePlanPresenter(io: _io)..print(plan);
      final apply = presenter.confirm(
        assumeYes: command['yes'] as bool,
        dryRun: command['dry-run'] as bool,
      );
      if (!apply) {
        return 0;
      }

      final report = await _projectOptimizer.run(plan);
      final output = report.output.trimRight();
      if (output.isNotEmpty) {
        _io.writeLine(output);
      }
      if (!report.transaction.success) {
        _io.writeLine('Project optimization failed.');
        _io.writeLine(
          report.restored
              ? 'Restoration status: completed. Project files were restored.'
              : 'Restoration status: incomplete or not required; inspect the '
                  'reported stages before retrying.',
        );
        return 1;
      }

      _io.writeLine('Completed stages');
      for (final stage in report.stages) {
        _io.writeLine('  ${stage.command}');
      }
      final audit = report.audit!;
      if (audit.missingAssets.isNotEmpty) {
        _io.writeLine('Missing assets');
        for (final asset in audit.missingAssets) {
          _io.writeLine('  $asset');
        }
      }
      if (audit.staleGeneratedMarkers.isNotEmpty) {
        _io.writeLine('Stale generated files');
        for (final path in audit.staleGeneratedMarkers) {
          _io.writeLine('  $path');
        }
      }
      if (audit.unsupportedMarkers.isNotEmpty) {
        _io.writeLine('Unsupported source checks');
        for (final path in audit.unsupportedMarkers) {
          _io.writeLine('  $path');
        }
      }
      _io.writeLine(
        report.success
            ? 'Project health checks passed.'
            : 'Project health checks found issues.',
      );
      return report.success ? 0 : 1;
    } on ProjectInspectionException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on ProjectAuditException catch (error) {
      _io.writeLine('Project audit failed: ${error.message}');
      return 1;
    } on Exception catch (error) {
      _io.writeLine('Project optimization failed: $error');
      return 1;
    }
  }

  Future<int> _runArrange(ArgResults command) async {
    final nestedCommand = command.command;
    if (nestedCommand == null || nestedCommand.name != 'model') {
      _io.writeLine('Usage: gold_flutter arrange model [options]');
      return 64;
    }
    return _runArrangeModel(nestedCommand);
  }

  Future<int> _runArrangeModel(ArgResults command) async {
    final path = (command['path'] as String?)?.trim();
    if (path == null || path.isEmpty) {
      _io.writeLine('--path is required.');
      return 64;
    }

    try {
      final project = await const ProjectInspector().inspect(_currentDirectory);
      if (project.isDirty) {
        _io.writeLine(
          'Warning: the project has uncommitted Git changes.',
        );
      }
      final plan = await _modelArranger.plan(
        project: project,
        path: path,
        addCopyWith: command['copy-with'] as bool,
        addTest: command['test'] as bool,
      );
      final presenter = ChangePlanPresenter(io: _io)..print(plan);
      final apply = presenter.confirm(
        assumeYes: command['yes'] as bool,
        dryRun: command['dry-run'] as bool,
      );
      if (!apply) {
        return 0;
      }

      final report = await _changeTransaction.execute(plan);
      final output = report.output.trimRight();
      if (!report.success) {
        _writeArrangementFailure(report, output);
        return 1;
      }
      if (output.isNotEmpty) {
        _io.writeLine(output);
      }
      presenter.printReport(report, preserved: plan.preserved);
      _io.writeLine('Model arrangement applied.');
      return 0;
    } on ModelArrangementException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on ProjectInspectionException catch (error) {
      _io.writeLine(error.message);
      return 64;
    } on Exception catch (error) {
      _io.writeLine('Model arrangement failed: $error');
      _io.writeLine(
        'Restoration status: not needed; the transaction did not start.',
      );
      _io.writeLine(
        'Suggested next action: review the reported error and command input, '
        'then run the command again.',
      );
      return 1;
    }
  }

  void _writeArrangementFailure(ChangeReport report, String output) {
    _io.writeLine('Failure details');
    _io.writeLine(
      output.isEmpty ? 'No tool output was captured.' : output,
    );
    _io.writeLine('Model arrangement failed.');
    if (report.restored) {
      _io.writeLine(
        'Restoration status: completed. Changes were restored.',
      );
      _io.writeLine(
        'Suggested next action: fix the reported operation or tool error, '
        'review the plan, and run the command again.',
      );
      return;
    }
    if (report.created.isEmpty && report.modified.isEmpty) {
      _io.writeLine(
        'Restoration status: not needed; no planned file was written.',
      );
      _io.writeLine(
        'Suggested next action: resolve the reported precondition or path '
        'change, review the plan, and run the command again.',
      );
      return;
    }
    _io.writeLine(
      'Restoration status: incomplete; inspect the planned files before '
      'retrying.',
    );
    _io.writeLine(
      'Suggested next action: inspect the reported files and restore any '
      'remaining changes before running the command again.',
    );
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
    parser.addCommand('optimize')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Preview detected health stages without running them.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Run the detected stages without confirmation.',
      );
    parser.addCommand('add').addCommand('amount-formatter')
      ..addOption('locale', defaultsTo: 'en_NG')
      ..addOption('symbol', defaultsTo: '₦')
      ..addOption('decimal-digits', defaultsTo: '2')
      ..addFlag(
        'grouping',
        defaultsTo: true,
        negatable: true,
        help: 'Display grouped thousands.',
      )
      ..addOption('hidden-text', defaultsTo: '₦ •••••')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Preview generated files and commands without applying them.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Use flag values and apply without confirmation.',
      );
    parser.addCommand('docs')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Preview generated documentation without writing it.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Generate documentation without confirmation.',
      );
    parser.addCommand('arrange').addCommand('model')
      ..addOption(
        'path',
        valueHelp: 'file',
        help: 'Dart model file under lib/domain/models/.',
      )
      ..addFlag(
        'copy-with',
        negatable: false,
        help: 'Add copyWith to eligible classes that do not define it.',
      )
      ..addFlag(
        'test',
        negatable: false,
        help: 'Add or update the Gold-owned focused model test.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Preview the complete plan without changing files.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Apply the plan without interactive confirmation.',
      );
    return parser;
  }

  void _writeHelp() {
    _io.writeLine('Gold Flutter $version');
    _io.writeLine('Create and maintain Riverpod + AutoRoute Flutter projects.');
    _io.writeLine('');
    _io.writeLine('Commands');
    _writeCatalogEntry(
      command: 'gold_flutter create',
      description: 'Create a complete new Flutter application.',
      location: 'Parent folder that should contain the project.',
    );
    _writeCatalogEntry(
      command: 'gold_flutter doctor',
      description: 'Check Flutter, Dart, and Git prerequisites.',
      location: 'Anywhere.',
    );
    _writeCatalogEntry(
      command: 'gold_flutter arrange model',
      description: 'Rewrite a supported model using defensive conventions.',
      location: 'Flutter project root or any folder inside it.',
    );
    _writeCatalogEntry(
      command: 'gold_flutter optimize',
      description: 'Run formatting, analysis, tests, and project audits.',
      location: 'Flutter project root or any folder inside it.',
    );
    _writeCatalogEntry(
      command: 'gold_flutter add amount-formatter',
      description: 'Install the tested reusable money formatter.',
      location: 'Flutter project root or any folder inside it.',
    );
    _writeCatalogEntry(
      command: 'gold_flutter docs',
      description: 'Generate project documentation safely.',
      location: 'Flutter project root or any folder inside it.',
    );
    _io.writeLine('');
    _io.writeLine('Need details? Run: gold_flutter help <command>');
    _io.writeLine('Example: gold_flutter help arrange model');
  }

  void _writeCatalogEntry({
    required String command,
    required String description,
    required String location,
  }) {
    _io.writeLine('  $command');
    _io.writeLine('    $description');
    _io.writeLine('    Run from: $location');
  }

  int _writeCommandHelp(ArgParser parser, List<String> path) {
    if (path.isEmpty) {
      _writeHelp();
      return 0;
    }

    final topic = path.join(' ');
    late final String usage;
    late final String description;
    late final String location;
    late final String example;
    late final ArgParser commandParser;
    switch (topic) {
      case 'create':
        usage = 'gold_flutter create [options]';
        description = 'Create a complete Riverpod + AutoRoute Flutter app.';
        location = 'Parent folder that should contain the new project.';
        example = 'gold_flutter create';
        commandParser = parser.commands['create']!;
      case 'doctor':
        usage = 'gold_flutter doctor';
        description = 'Check whether Flutter, Dart, and Git are ready.';
        location = 'Anywhere.';
        example = 'gold_flutter doctor';
        commandParser = parser.commands['doctor']!;
      case 'arrange model':
        usage = 'gold_flutter arrange model [options]';
        description = 'Safely rewrite a supported Dart model file.';
        location = 'Flutter project root or any folder inside it.';
        example = 'gold_flutter arrange model --path '
            'lib/domain/models/report_model.dart --dry-run';
        commandParser = parser.commands['arrange']!.commands['model']!;
      case 'optimize':
        usage = 'gold_flutter optimize [options]';
        description = 'Run the transparent project-health pipeline.';
        location = 'Flutter project root or any folder inside it.';
        example = 'gold_flutter optimize --dry-run';
        commandParser = parser.commands['optimize']!;
      case 'add amount-formatter':
        usage = 'gold_flutter add amount-formatter [options]';
        description = 'Install and test the reusable money formatter.';
        location = 'Flutter project root or any folder inside it.';
        example = 'gold_flutter add amount-formatter --dry-run';
        commandParser = parser.commands['add']!.commands['amount-formatter']!;
      case 'docs':
        usage = 'gold_flutter docs [options]';
        description = 'Generate safe, owned project documentation.';
        location = 'Flutter project root or any folder inside it.';
        example = 'gold_flutter docs --dry-run';
        commandParser = parser.commands['docs']!;
      default:
        _io.writeLine('Unknown help topic "$topic".');
        _io.writeLine('Run gold_flutter to see every command.');
        return 64;
    }

    _io.writeLine('Usage: $usage');
    _io.writeLine(description);
    _io.writeLine('Run from: $location');
    _io.writeLine('Example: $example');
    final options = commandParser.usage.trim();
    if (options.isNotEmpty) {
      _io.writeLine('');
      _io.writeLine('Options:');
      _io.writeLine(options);
    }
    return 0;
  }
}
