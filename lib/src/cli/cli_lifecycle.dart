import 'dart:io';

import '../process/process_executor.dart';
import '../prompts/prompt_io.dart';
import 'flutter_update_checker.dart';

/// Manages the Dart Pub CLI installation independently of generated projects.
final class CliLifecycle {
  CliLifecycle({
    required PromptIO io,
    FlutterUpdateChecker? checker,
    ProcessExecutor? executor,
    Map<String, String>? environment,
    String? dartExecutable,
  })  : _io = io,
        _checker = checker ?? FlutterUpdateChecker(),
        _executor = executor ?? const LocalProcessExecutor(),
        _environment = environment ?? Platform.environment,
        _dartExecutable = dartExecutable ?? Platform.resolvedExecutable;

  static const installCommand = 'dart pub global activate --source git '
      '--git-ref main https://github.com/crisantus/gold-flutter.git';
  static const uninstallCommand = 'dart pub global deactivate gold_flutter';

  final PromptIO _io;
  final FlutterUpdateChecker _checker;
  final ProcessExecutor _executor;
  final Map<String, String> _environment;
  final String _dartExecutable;

  Future<void> beforeCreate({required bool enabled}) async {
    final ci = (_environment['CI'] ?? '').toLowerCase();
    final disabled =
        (_environment['GOLD_FLUTTER_NO_UPDATE_CHECK'] ?? '').toLowerCase();
    if (!enabled ||
        (ci.isNotEmpty && ci != 'false' && ci != '0') ||
        disabled == '1' ||
        disabled == 'true') {
      return;
    }
    _printResult(await _checker.check(), explicit: false);
  }

  Future<int> checkUpdate() async {
    final result = await _checker.check();
    _printResult(result, explicit: true);
    return result.status == UpdateStatus.unavailable ||
            result.status == UpdateStatus.unknown
        ? 1
        : 0;
  }

  Future<int> update() => _runPub(
        [
          'global',
          'activate',
          '--source',
          'git',
          '--git-ref',
          'main',
          'https://github.com/crisantus/gold-flutter.git'
        ],
        action: 'Updating Gold Flutter from GitHub main',
        success:
            'Gold Flutter updated. Run gold_flutter --version to check it. '
            'Existing Flutter projects are unchanged.',
        fallback: installCommand,
      );

  Future<int> uninstall() => _runPub(
        ['global', 'deactivate', 'gold_flutter'],
        action: 'Uninstalling the Gold Flutter CLI',
        success: 'Gold Flutter CLI uninstalled. '
            'Your Flutter projects and their dependencies are unchanged.',
        fallback: uninstallCommand,
      );

  Future<int> _runPub(
    List<String> arguments, {
    required String action,
    required String success,
    required String fallback,
  }) async {
    _io.writeLine('$action...');
    try {
      // Pub inherits PUB_CACHE and handles its own installation files. It never
      // receives an application path or a command supplied by a remote server.
      final output = await _executor.run(
        _dartExecutable,
        ['pub', ...arguments],
        workingDirectory: Directory.systemTemp,
      );
      for (final text in [output.stdout, output.stderr]) {
        if (text.trim().isNotEmpty) _io.writeLine(text.trimRight());
      }
      if (output.exitCode != 0) {
        _io.writeLine('Dart Pub failed. Retry manually: $fallback');
        return output.exitCode;
      }
      _io.writeLine(success);
      return 0;
    } on Exception catch (error) {
      _io.writeLine('Unable to run Dart Pub: $error');
      _io.writeLine('Run manually: $fallback');
      return 1;
    }
  }

  void _printResult(UpdateResult result, {required bool explicit}) {
    switch (result.status) {
      case UpdateStatus.current:
        if (explicit) {
          _io.writeLine('Gold Flutter is up to date with GitHub main.');
        }
      case UpdateStatus.ahead:
        if (explicit) {
          _io.writeLine('Your installed commit is ahead of GitHub main.');
        }
      case UpdateStatus.unavailable:
        _io.writeLine('GitHub update check unavailable (offline, timeout, or '
            'rate limit). You can continue creating projects. '
            'Check later with: gold_flutter check-update');
      case UpdateStatus.unknown:
        _io.writeLine('This installation has no Git revision metadata. '
            'Install from GitHub to enable update checks:\n  $installCommand\n'
            'You can continue using the installed version.');
      case UpdateStatus.available:
      case UpdateStatus.diverged:
        final title = result.status == UpdateStatus.available
            ? 'A Gold Flutter update is available'
            : 'GitHub main has diverged from your installed commit';
        _io.writeLine('$title '
            '(${result.installed!.substring(0, 8)} -> '
            '${result.latest!.substring(0, 8)}).\n'
            'Update now: gold_flutter update\n'
            'Or run: $installCommand\n'
            'You can ignore this notice and continue with the installed version.');
    }
  }
}
