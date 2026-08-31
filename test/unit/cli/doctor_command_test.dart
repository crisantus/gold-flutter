import 'dart:io';

import 'package:gold_flutter/src/cli/doctor_command.dart';
import 'package:test/test.dart';

import '../../support/fake_process_executor.dart';

void main() {
  test('reports every required executable and writable directory', () async {
    final root = await Directory.systemTemp.createTemp('gold_doctor_test_');
    addTearDown(() => root.delete(recursive: true));
    final executor = FakeProcessExecutor.success({
      'flutter --version': 'Flutter 3.x',
      'dart --version': 'Dart 3.x',
      'git --version': 'git version 2.x',
    });

    final report = await DoctorCommand(
      executor: executor,
      workingDirectory: root,
    ).run();

    expect(report.checks.map((item) => item.name), [
      'Flutter',
      'Dart',
      'Git',
      'Current directory',
    ]);
    expect(report.isHealthy, isTrue);
  });

  test('keeps checking after one executable fails', () async {
    final root = await Directory.systemTemp.createTemp('gold_doctor_test_');
    addTearDown(() => root.delete(recursive: true));
    final executor = FakeProcessExecutor.success({
      'dart --version': 'Dart 3.x',
      'git --version': 'git version 2.x',
    });

    final report = await DoctorCommand(
      executor: executor,
      workingDirectory: root,
    ).run();

    expect(report.isHealthy, isFalse);
    expect(executor.calls,
        ['flutter --version', 'dart --version', 'git --version']);
  });
}
