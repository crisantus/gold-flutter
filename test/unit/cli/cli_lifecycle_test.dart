import 'dart:async';
import 'dart:io';

import 'package:gold_flutter/src/cli/cli_lifecycle.dart';
import 'package:gold_flutter/src/cli/flutter_update_checker.dart';
import 'package:gold_flutter/src/cli/gold_flutter_cli.dart';
import 'package:gold_flutter/src/config/project_answers.dart';
import 'package:gold_flutter/src/generator/project_generator.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:test/test.dart';

import '../../support/fake_process_executor.dart';
import '../../support/fake_prompt_io.dart';

const installed = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const latest = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

FlutterUpdateChecker checker({String status = 'ahead'}) => FlutterUpdateChecker(
      revisionReader: () async => installed,
      jsonReader: (uri) async => uri.path.contains('/compare/')
          ? {'status': status}
          : {
              'object': {'sha': latest}
            },
    );

void main() {
  group('GitHub commit checks', () {
    for (final entry in {
      'ahead': UpdateStatus.available,
      'behind': UpdateStatus.ahead,
      'identical': UpdateStatus.current,
      'diverged': UpdateStatus.diverged,
      'unexpected': UpdateStatus.unavailable,
    }.entries) {
      test('maps GitHub ${entry.key} without version-number assumptions',
          () async {
        final result = await checker(status: entry.key).check();
        expect(result.status, entry.value);
        expect(result.installed, installed);
        expect(result.latest, latest);
      });
    }

    test('an identical SHA needs only one request to the trusted main branch',
        () async {
      final requests = <Uri>[];
      final result = await FlutterUpdateChecker(
        revisionReader: () async => installed,
        jsonReader: (uri) async {
          requests.add(uri);
          return {
            'object': {'sha': installed}
          };
        },
      ).check();
      expect(result.status, UpdateStatus.current);
      expect(requests.single.toString(),
          'https://api.github.com/repos/crisantus/gold-flutter/git/ref/heads/main');
    });

    test('unknown installation does not report current or contact GitHub',
        () async {
      final result = await FlutterUpdateChecker(
        revisionReader: () async => null,
        jsonReader: (_) async => fail('Unexpected network call'),
      ).check();
      expect(result.status, UpdateStatus.unknown);
    });

    for (final value in [
      null,
      [],
      {},
      {
        'object': {'sha': 'bad-sha'}
      }
    ]) {
      test('rejects malformed GitHub reference $value', () async {
        final result = await FlutterUpdateChecker(
          revisionReader: () async => installed,
          jsonReader: (_) async => value,
        ).check();
        expect(result.status, UpdateStatus.unavailable);
      });
    }

    test('offline, rate-limit, and invalid JSON failures are unavailable',
        () async {
      for (final error in [
        const SocketException('Offline'),
        const HttpException('Rate limit'),
        const FormatException('Invalid JSON'),
      ]) {
        final result = await FlutterUpdateChecker(
          revisionReader: () async => installed,
          jsonReader: (_) async => throw error,
        ).check();
        expect(result.status, UpdateStatus.unavailable);
      }
    });

    test('deadline covers a stalled response and revision lookup', () async {
      final stalled = Completer<Object?>();
      final result = await FlutterUpdateChecker(
        revisionReader: () async => installed,
        jsonReader: (_) => stalled.future,
        timeout: const Duration(milliseconds: 15),
      ).check();
      expect(result.status, UpdateStatus.unavailable);
      final unknownRevision = Completer<String?>();
      expect(
        (await FlutterUpdateChecker(
          revisionReader: () => unknownRevision.future,
          timeout: const Duration(milliseconds: 15),
        ).check())
            .status,
        UpdateStatus.unavailable,
      );
    });
  });

  group('CLI lifecycle commands', () {
    for (final entry in {
      'update': 'pub global activate --source git --git-ref main '
          'https://github.com/crisantus/gold-flutter.git',
      'uninstall': 'pub global deactivate gold_flutter',
    }.entries) {
      test(
          '${entry.key} delegates only to Dart Pub and preserves project files',
          () async {
        final project = await Directory.systemTemp.createTemp('gold-app-');
        addTearDown(() => project.delete(recursive: true));
        final app = File('${project.path}/pubspec.yaml');
        await app.writeAsString('name: keep_this_app\n');
        final io = FakePromptIO([]);
        final executor =
            FakeProcessExecutor.success({'dart ${entry.value}': ''});
        final lifecycle = CliLifecycle(
          io: io,
          executor: executor,
          dartExecutable: 'dart',
        );
        final code = await GoldFlutterCli(
          io: io,
          currentDirectory: project,
          lifecycle: lifecycle,
        ).run([entry.key]);
        expect(code, 0);
        expect(executor.calls, ['dart ${entry.value}']);
        expect(await app.readAsString(), 'name: keep_this_app\n');
        expect(io.output.last, contains('unchanged'));
      });

      test('${entry.key} reports Pub failure instead of claiming success',
          () async {
        final io = FakePromptIO([]);
        final lifecycle = CliLifecycle(
          io: io,
          dartExecutable: 'dart',
          executor: FakeProcessExecutor({
            'dart ${entry.value}': const ProcessOutput(
              exitCode: 69,
              stdout: '',
              stderr: 'Network unavailable',
            ),
          }),
        );
        expect(
            await GoldFlutterCli(io: io, lifecycle: lifecycle).run([entry.key]),
            69);
        expect(io.output.join('\n'), contains('Retry manually: dart'));
        expect(io.output.join('\n'), contains('Network unavailable'));
      });
    }

    test('subprocess startup failures provide the manual fallback', () async {
      final io = FakePromptIO([]);
      expect(
          await CliLifecycle(io: io, executor: _ThrowingExecutor()).uninstall(),
          1);
      expect(io.output.last, contains(CliLifecycle.uninstallCommand));
    });

    test('check-update is explicit even when CI disables automatic checks',
        () async {
      final io = FakePromptIO([]);
      final lifecycle = CliLifecycle(
        io: io,
        checker: checker(),
        environment: {'CI': 'true'},
      );
      expect(
          await GoldFlutterCli(io: io, lifecycle: lifecycle)
              .run(['check-update']),
          0);
      final output = io.output.join('\n');
      expect(output, contains('update is available'));
      expect(output, contains('gold_flutter update'));
      expect(output, contains(CliLifecycle.installCommand));
      expect(output, contains('ignore this notice'));
    });

    test('unavailable and unknown checks exit nonzero with honest messages',
        () async {
      for (final revision in [null, installed]) {
        final io = FakePromptIO([]);
        final lifecycle = CliLifecycle(
          io: io,
          checker: FlutterUpdateChecker(
            revisionReader: () async => revision,
            jsonReader: (_) async => throw const SocketException('offline'),
          ),
        );
        expect(await lifecycle.checkUpdate(), 1);
        expect(io.output.join('\n'), isNot(contains('up to date')));
      }
    });

    for (final command in ['check-update', 'update', 'uninstall']) {
      test('$command is discoverable and help never performs an action',
          () async {
        final io = FakePromptIO([]);
        final executor = FakeProcessExecutor(const {});
        final cli = GoldFlutterCli(
            io: io,
            lifecycle: CliLifecycle(
              io: io,
              executor: executor,
            ));
        expect(await cli.run([]), 0);
        expect(io.output.join('\n'), contains('gold_flutter $command'));
        expect(await cli.run([command, '--help']), 0);
        expect(io.output.join('\n'), contains('Run from: Anywhere.'));
        expect(executor.calls, isEmpty);
      });
    }
  });

  group('optional checks before creation', () {
    for (final environment in [
      {'CI': 'true'},
      {'CI': '1'},
      {'GOLD_FLUTTER_NO_UPDATE_CHECK': '1'},
      {'GOLD_FLUTTER_NO_UPDATE_CHECK': 'true'},
    ]) {
      test('skips automatic network calls for $environment', () async {
        final io = FakePromptIO([]);
        await CliLifecycle(
          io: io,
          environment: environment,
          checker: FlutterUpdateChecker(
            revisionReader: () async => fail('Unexpected check'),
          ),
        ).beforeCreate(enabled: true);
        expect(io.output, isEmpty);
      });
    }

    for (final skip in [true, false]) {
      test('create continues after a notice; skip flag suppresses it ($skip)',
          () async {
        final io = FakePromptIO([]);
        final generator = _RecordingGenerator(io);
        final code = await GoldFlutterCli(
          io: io,
          generator: generator,
          lifecycle: CliLifecycle(io: io, checker: checker(), environment: {}),
        ).run([
          'create',
          if (skip) '--no-update-check',
          '--display-name',
          'Sample',
          '--project-name',
          'sample',
          '--application-id',
          'com.example.sample',
          '--platforms',
          'android',
          '--yes',
        ]);
        expect(code, 0);
        expect(generator.called, isTrue);
        expect(
            generator.outputBeforeGeneration.join('\n'),
            skip
                ? isNot(contains('update is available'))
                : contains('update is available'));
        expect(io.prompts, isEmpty);
      });
    }

    test('network failure does not block create', () async {
      final io = FakePromptIO([]);
      final generator = _RecordingGenerator(io);
      final code = await GoldFlutterCli(
        io: io,
        generator: generator,
        lifecycle: CliLifecycle(
            io: io,
            environment: {},
            checker: FlutterUpdateChecker(
                revisionReader: () async => installed,
                jsonReader: (_) async =>
                    throw const SocketException('Offline'))),
      ).run([
        'create',
        '--display-name',
        'App',
        '--project-name',
        'app',
        '--application-id',
        'com.example.app',
        '--platforms',
        'android',
        '--yes'
      ]);
      expect(code, 0);
      expect(generator.called, isTrue);
      expect(io.output.join('\n'), contains('check unavailable'));
    });
  });
}

final class _RecordingGenerator implements ProjectGenerator {
  _RecordingGenerator(this.io);
  final FakePromptIO io;
  bool called = false;
  List<String> outputBeforeGeneration = [];

  @override
  Future<Directory> generate({
    required ProjectAnswers answers,
    required Directory destinationParent,
  }) async {
    called = true;
    outputBeforeGeneration = List.of(io.output);
    return Directory('${destinationParent.path}/${answers.projectName}');
  }
}

final class _ThrowingExecutor implements ProcessExecutor {
  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    void Function()? onStarted,
  }) async =>
      throw const ProcessException('dart', [], 'Not available');
}
