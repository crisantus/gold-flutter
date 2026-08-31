import 'dart:io';

import 'package:gold_flutter/src/change/change_plan.dart';
import 'package:gold_flutter/src/change/change_transaction.dart';
import 'package:gold_flutter/src/model/model_arranger.dart';
import 'package:gold_flutter/src/model/model_test_renderer.dart';
import 'package:gold_flutter/src/process/process_executor.dart';
import 'package:gold_flutter/src/project/project_inspection.dart';
import 'package:test/test.dart';

import '../../support/fake_process_executor.dart';
import '../../support/project_fixture.dart';

void main() {
  const arranger = ModelArranger();

  test('rejects a model path outside the inspected project', () async {
    final fixture = await ProjectFixture.create();
    final outside = await Directory.systemTemp.createTemp('gold_outside_');
    addTearDown(fixture.dispose);
    addTearDown(() => outside.delete(recursive: true));
    final outsideModel = File('${outside.path}/report_model.dart');
    await outsideModel.writeAsString(_supportedModel);

    expect(
      () => arranger.plan(
        project: _inspection(fixture),
        path: outsideModel.path,
        addCopyWith: false,
        addTest: false,
      ),
      throwsA(isA<ModelArrangementException>()),
    );
  });

  test('rejects traversal even when normalization returns inside the project',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _supportedModel},
    );
    addTearDown(fixture.dispose);

    expect(
      () => arranger.plan(
        project: _inspection(fixture),
        path: 'lib/domain/../domain/models/report_model.dart',
        addCopyWith: false,
        addTest: false,
      ),
      throwsA(isA<ModelArrangementException>()),
    );
  });

  test('rejects non-model, non-Dart, and missing source paths', () async {
    final fixture = await ProjectFixture.create(
      files: {
        'lib/feature/report_model.dart': _supportedModel,
        'lib/domain/models/report_model.txt': _supportedModel,
      },
    );
    addTearDown(fixture.dispose);

    for (final path in const [
      'lib/feature/report_model.dart',
      'lib/domain/models/report_model.txt',
      'lib/domain/models/missing.dart',
    ]) {
      expect(
        () => arranger.plan(
          project: _inspection(fixture),
          path: path,
          addCopyWith: false,
          addTest: false,
        ),
        throwsA(isA<ModelArrangementException>()),
        reason: path,
      );
    }
  });

  test('rejects a model reached through a project child symlink', () async {
    final fixture = await ProjectFixture.create();
    final outside = await Directory.systemTemp.createTemp('gold_outside_');
    addTearDown(fixture.dispose);
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}/report_model.dart')
        .writeAsString(_supportedModel);
    await Directory('${fixture.root.path}/lib/domain').create(recursive: true);
    await Link('${fixture.root.path}/lib/domain/models').create(outside.path);

    expect(
      () => arranger.plan(
        project: _inspection(fixture),
        path: 'lib/domain/models/report_model.dart',
        addCopyWith: false,
        addTest: false,
      ),
      throwsA(isA<ModelArrangementException>()),
    );
  });

  test('turns unsupported parser diagnostics into an arrangement error',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _unsupportedModel},
    );
    addTearDown(fixture.dispose);

    expect(
      () => arranger.plan(
        project: _inspection(fixture),
        path: 'lib/domain/models/report_model.dart',
        addCopyWith: false,
        addTest: false,
      ),
      throwsA(
        isA<ModelArrangementException>().having(
          (error) => error.message,
          'message',
          contains('ReportModel.grouped'),
        ),
      ),
    );
  });

  test('plans one model write, covered format, and non-mutating analysis',
      () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _supportedModel},
    );
    addTearDown(fixture.dispose);

    final plan = await arranger.plan(
      project: _inspection(fixture),
      path: 'lib/domain/models/report_model.dart',
      addCopyWith: false,
      addTest: false,
    );

    expect(plan.files, hasLength(1));
    expect(
        plan.files.single.relativePath, 'lib/domain/models/report_model.dart');
    expect(plan.files.single.kind, FileChangeKind.modify);
    expect(
      plan.files.single.reason,
      'Arrange models using the EyeAsk standard',
    );
    expect(plan.commands, hasLength(2));
    expect(plan.commands[0].executable, 'dart');
    expect(plan.commands[0].arguments,
        ['format', 'lib/domain/models/report_model.dart']);
    expect(plan.commands[0].mutatesFiles, isTrue);
    expect(plan.commands[1].executable, 'flutter');
    expect(plan.commands[1].arguments, ['analyze']);
    expect(plan.commands[1].mutatesFiles, isFalse);
  });

  test('creates and formats a missing owned focused test', () async {
    final fixture = await ProjectFixture.create(
      files: {'lib/domain/models/report_model.dart': _supportedModel},
    );
    addTearDown(fixture.dispose);

    final plan = await arranger.plan(
      project: _inspection(fixture),
      path: 'lib/domain/models/report_model.dart',
      addCopyWith: false,
      addTest: true,
    );

    expect(plan.files, hasLength(2));
    expect(
      plan.files[1].relativePath,
      'test/domain/models/report_model_test.dart',
    );
    expect(plan.files[1].kind, FileChangeKind.create);
    expect(
      plan.files[1].content.split('\n').first,
      ModelTestRenderer.ownershipMarker,
    );
    expect(plan.commands[0].arguments, [
      'format',
      'lib/domain/models/report_model.dart',
      'test/domain/models/report_model_test.dart',
    ]);
    expect(plan.commands[2].executable, 'flutter');
    expect(plan.commands[2].arguments,
        ['test', 'test/domain/models/report_model_test.dart']);
    expect(plan.commands[2].mutatesFiles, isFalse);
  });

  test('updates an existing Gold-owned test but preserves a non-owned test',
      () async {
    final fixture = await ProjectFixture.create(
      files: {
        'lib/domain/models/report_model.dart': _supportedModel,
        'test/domain/models/report_model_test.dart':
            '${ModelTestRenderer.ownershipMarker}\nold generated test\n',
      },
    );
    addTearDown(fixture.dispose);

    final ownedPlan = await arranger.plan(
      project: _inspection(fixture),
      path: 'lib/domain/models/report_model.dart',
      addCopyWith: false,
      addTest: true,
    );

    expect(ownedPlan.files[1].kind, FileChangeKind.modify);

    await fixture.write(
      'test/domain/models/report_model_test.dart',
      '// Maintained by the application team.\n',
    );
    final preservedPlan = await arranger.plan(
      project: _inspection(fixture),
      path: 'lib/domain/models/report_model.dart',
      addCopyWith: false,
      addTest: true,
    );

    expect(preservedPlan.files, hasLength(1));
    expect(preservedPlan.summary, contains('Preserve non-Gold test'));
    expect(preservedPlan.summary,
        contains('test/domain/models/report_model_test.dart'));
    expect(preservedPlan.commands[0].arguments,
        ['format', 'lib/domain/models/report_model.dart']);
    expect(
      preservedPlan.commands,
      isNot(
        contains(
          isA<PlannedCommand>().having(
            (command) => command.arguments,
            'arguments',
            ['test', 'test/domain/models/report_model_test.dart'],
          ),
        ),
      ),
    );
  });

  test('real transaction restores the model and owned test on analyze failure',
      () async {
    const originalTest =
        '${ModelTestRenderer.ownershipMarker}\nold generated test\n';
    final fixture = await ProjectFixture.create(
      files: {
        'lib/domain/models/report_model.dart': _supportedModel,
        'test/domain/models/report_model_test.dart': originalTest,
      },
    );
    addTearDown(fixture.dispose);
    final plan = await arranger.plan(
      project: _inspection(fixture),
      path: 'lib/domain/models/report_model.dart',
      addCopyWith: true,
      addTest: true,
    );
    final executor = FakeProcessExecutor({
      'dart format lib/domain/models/report_model.dart '
              'test/domain/models/report_model_test.dart':
          const ProcessOutput(exitCode: 0, stdout: 'formatted', stderr: ''),
      'flutter analyze': const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'fake analyzer failure',
      ),
    });

    final report = await ChangeTransaction(executor: executor).execute(plan);

    expect(report.success, isFalse);
    expect(report.restored, isTrue);
    expect(executor.calls, [
      'dart format lib/domain/models/report_model.dart '
          'test/domain/models/report_model_test.dart',
      'flutter analyze',
    ]);
    expect(
      fixture.file('lib/domain/models/report_model.dart').readAsStringSync(),
      _supportedModel,
    );
    expect(
      fixture
          .file('test/domain/models/report_model_test.dart')
          .readAsStringSync(),
      originalTest,
    );
  });
}

ProjectInspection _inspection(ProjectFixture fixture) => ProjectInspection(
      root: fixture.root,
      projectName: 'fixture',
      dependencies: const {'flutter'},
      assets: const [],
      hasTests: true,
      hasGit: false,
      isDirty: false,
    );

const _supportedModel = r'''class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );
}
''';

const _unsupportedModel = r'''class ReportModel {
  final Map<String, List<Object?>> grouped;

  ReportModel({required this.grouped});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        grouped: json?["grouped"] as Map<String, List<Object?>>,
      );
}
''';
