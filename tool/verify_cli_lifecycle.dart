// Run with `dart run tool/verify_cli_lifecycle.dart [--live-update]`.
// Every activation uses a temporary PUB_CACHE, never the user's installation.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final temporary = await Directory.systemTemp.createTemp('gold-cli-smoke-');
  final source = Directory('${temporary.path}/source')..createSync();
  final cache = Directory('${temporary.path}/pub-cache');
  final project = Directory('${temporary.path}/existing-app')..createSync();
  final environment = {...Platform.environment, 'PUB_CACHE': cache.path};

  Future<ProcessResult> run(String executable, List<String> args,
      {Directory? directory}) async {
    final result = await Process.run(executable, args,
        workingDirectory: (directory ?? project).path,
        environment: environment,
        runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      throw StateError('$executable ${args.join(' ')} failed:\n'
          '${result.stdout}\n${result.stderr}');
    }
    return result;
  }

  Future<String> dart(List<String> args) async =>
      (await run(Platform.resolvedExecutable, args)).stdout.toString().trim();
  Future<String> cli(List<String> args) =>
      dart(['pub', 'global', 'run', 'gold_flutter:gold_flutter', ...args]);
  Future<void> activate() async {
    await dart([
      'pub',
      'global',
      'activate',
      '--source',
      'git',
      '--git-ref',
      'main',
      source.uri.toString()
    ]);
  }

  Future<String> commit(String message) async {
    await run('git', ['add', '.'], directory: source);
    await run(
        'git',
        [
          '-c',
          'user.name=Gold CLI test',
          '-c',
          'user.email=gold-cli-test@example.invalid',
          'commit',
          '-m',
          message
        ],
        directory: source);
    return (await run('git', ['rev-parse', 'HEAD'], directory: source))
        .stdout
        .toString()
        .trim();
  }

  Future<String> revision() =>
      dart(['pub', 'global', 'run', 'gold_flutter:installed_revision']);
  Future<String> snapshot() async {
    final files = <String, String>{};
    await for (final entry in project.list(recursive: true)) {
      if (entry is File) {
        files[entry.path.substring(project.path.length)] =
            base64Encode(await entry.readAsBytes());
      }
    }
    final keys = files.keys.toList()..sort();
    return jsonEncode({for (final key in keys) key: files[key]});
  }

  try {
    for (final folder in ['bin', 'lib']) {
      await _copy(Directory('${root.path}/$folder'),
          Directory('${source.path}/$folder'));
    }
    for (final name in ['pubspec.yaml', 'pubspec.lock']) {
      await File('${root.path}/$name').copy('${source.path}/$name');
    }
    await File('${source.path}/bin/installed_revision.dart').writeAsString('''
import 'package:gold_flutter/src/cli/flutter_update_checker.dart';
Future<void> main() async {
  print(await FlutterUpdateChecker.readInstalledRevision());
}
''');
    for (final entry in {
      'pubspec.yaml': 'name: existing_app\n',
      'lib/main.dart': 'void main() {}\n',
      'AGENTS.md': 'Keep application guidance.\n',
      '.agents/skills/example/SKILL.md': 'Keep application skills.\n',
      'docs/gold_flutter/commands.md': 'Keep generated guides.\n',
    }.entries) {
      final file = File('${project.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    final original = await snapshot();
    await run('git', ['init', '-b', 'main'], directory: source);
    final first = await commit('First CLI build');
    stdout.writeln('Installing into an isolated Pub cache...');
    await activate();
    if (!(await revision()).endsWith(first)) {
      throw StateError(
          'Installed snapshot did not resolve its own Git commit.');
    }
    final version = await cli(['--version']);
    await File('${source.path}/same-version-change.txt').writeAsString('new');
    final second = await commit('Change without a version bump');
    await activate();
    if (!(await revision()).endsWith(second) ||
        await cli(['--version']) != version) {
      throw StateError('Reactivation failed to update the same-version build.');
    }
    stdout.writeln('Verified installed revision and same-version Git update.');

    if (arguments.contains('--live-update')) {
      stdout.writeln('Running the real update command against GitHub...');
      final output = await cli(['update']);
      if (!output.contains('Gold Flutter updated.')) {
        throw StateError('The update command did not report success: $output');
      }
      final lock =
          File('${cache.path}/global_packages/gold_flutter/pubspec.lock');
      if (!(await lock.readAsString())
          .contains('https://github.com/crisantus/gold-flutter.git')) {
        throw StateError(
            'Update did not activate the official Git repository.');
      }
      // Restore the local build, since GitHub may not yet contain uninstall.
      await activate();
      stdout.writeln('Verified the real Dart Pub update from GitHub.');
    }

    final output = await cli(['uninstall']);
    if (!output.contains('Gold Flutter CLI uninstalled.') ||
        await Directory('${cache.path}/global_packages/gold_flutter')
            .exists()) {
      throw StateError('Uninstall did not remove the isolated activation.');
    }
    if (await snapshot() != original) {
      throw StateError(
          'Lifecycle commands changed existing application files.');
    }
    stdout
        .writeln('Verified uninstall and preservation of every project file.');
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> _copy(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entry in source.list()) {
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final destination = '${target.path}/$name';
    if (entry is Directory) {
      await _copy(entry, Directory(destination));
    } else if (entry is File) {
      await entry.copy(destination);
    }
  }
}
