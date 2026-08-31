import 'dart:io';

import '../process/process_executor.dart';

final class DoctorCheck {
  const DoctorCheck({
    required this.name,
    required this.isHealthy,
    required this.detail,
  });

  final String name;
  final bool isHealthy;
  final String detail;
}

final class DoctorReport {
  const DoctorReport(this.checks);

  final List<DoctorCheck> checks;

  bool get isHealthy => checks.every((check) => check.isHealthy);
}

final class DoctorCommand {
  const DoctorCommand({
    required ProcessExecutor executor,
    required Directory workingDirectory,
  })  : _executor = executor,
        _workingDirectory = workingDirectory;

  final ProcessExecutor _executor;
  final Directory _workingDirectory;

  Future<DoctorReport> run() async {
    final checks = <DoctorCheck>[];
    for (final command in const [
      (name: 'Flutter', executable: 'flutter', arguments: ['--version']),
      (name: 'Dart', executable: 'dart', arguments: ['--version']),
      (name: 'Git', executable: 'git', arguments: ['--version']),
    ]) {
      try {
        final result = await _executor.run(
          command.executable,
          command.arguments,
          workingDirectory: _workingDirectory,
        );
        final detail = result.exitCode == 0
            ? _firstNonEmptyLine(result.stdout, result.stderr)
            : _firstNonEmptyLine(result.stderr, result.stdout);
        checks.add(
          DoctorCheck(
            name: command.name,
            isHealthy: result.exitCode == 0,
            detail: detail.isEmpty
                ? (result.exitCode == 0 ? 'Available' : 'Not available')
                : detail,
          ),
        );
      } on Exception catch (error) {
        checks.add(
          DoctorCheck(
            name: command.name,
            isHealthy: false,
            detail: error.toString(),
          ),
        );
      }
    }
    checks.add(await _checkWorkingDirectory());
    return DoctorReport(List.unmodifiable(checks));
  }

  Future<DoctorCheck> _checkWorkingDirectory() async {
    File? probe;
    try {
      if (!await _workingDirectory.exists()) {
        return const DoctorCheck(
          name: 'Current directory',
          isHealthy: false,
          detail: 'Directory does not exist.',
        );
      }
      probe = File(
        '${_workingDirectory.path}${Platform.pathSeparator}'
        '.gold_flutter_doctor_${pid}_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.create(exclusive: true);
      await probe.delete();
      return const DoctorCheck(
        name: 'Current directory',
        isHealthy: true,
        detail: 'Writable',
      );
    } on Exception catch (error) {
      if (probe != null && await probe.exists()) {
        await probe.delete();
      }
      return DoctorCheck(
        name: 'Current directory',
        isHealthy: false,
        detail: 'Not writable: $error',
      );
    }
  }

  String _firstNonEmptyLine(String first, String second) {
    for (final value in [first, second]) {
      for (final line in value.split(RegExp(r'[\r\n]+'))) {
        if (line.trim().isNotEmpty) return line.trim();
      }
    }
    return '';
  }
}
