import 'package:gold_flutter/src/optimize/optimization_detector.dart';
import 'package:gold_flutter/src/optimize/optimization_stage.dart';
import 'package:gold_flutter/src/project/project_inspector.dart';
import 'package:test/test.dart';

import '../../support/project_fixture.dart';

void main() {
  test('detects health stages in their required order', () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.yaml': '''
name: fixture
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.4.0
''',
      'lib/core/route/app_router.dart': "part 'app_router.gr.dart';\n",
      'test/widget_test.dart': '',
    });
    addTearDown(fixture.dispose);

    final project = await const ProjectInspector().inspect(fixture.root);
    final stages = await const OptimizationDetector().detect(project);

    expect(stages.map((stage) => stage.kind), [
      OptimizationStageKind.pubGet,
      OptimizationStageKind.buildRunner,
      OptimizationStageKind.format,
      OptimizationStageKind.analyze,
      OptimizationStageKind.test,
    ]);
    expect(
      stages.map((stage) => stage.command),
      [
        'flutter pub get',
        'dart run build_runner build --delete-conflicting-outputs',
        'dart format lib test',
        'flutter analyze',
        'flutter test',
      ],
    );
  });

  test('omits build runner, missing format roots, and missing tests', () async {
    final fixture = await ProjectFixture.create();
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final stages = await const OptimizationDetector().detect(project);

    expect(stages.map((stage) => stage.kind), [
      OptimizationStageKind.pubGet,
      OptimizationStageKind.analyze,
    ]);
  });
}
