import 'package:gold_flutter/src/optimize/project_auditor.dart';
import 'package:gold_flutter/src/project/project_inspector.dart';
import 'package:test/test.dart';

import '../../support/project_fixture.dart';

void main() {
  test('reports missing declared assets and generated part files', () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.yaml': '''
name: fixture
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
    - assets/images/
    - assets/missing.png
''',
      'assets/images/.keep': '',
      'lib/app_router.dart': "part 'app_router.gr.dart';\n",
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final audit = await const ProjectAuditor().audit(project);

    expect(audit.healthyAssets, ['assets/images/']);
    expect(audit.missingAssets, ['assets/missing.png']);
    expect(audit.staleGeneratedMarkers, ['lib/app_router.gr.dart']);
    expect(audit.isHealthy, isFalse);
  });

  test('rejects asset traversal', () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.yaml': '''
name: fixture
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
    - ../private/
''',
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    expect(
      () => const ProjectAuditor().audit(project),
      throwsA(isA<ProjectAuditException>()),
    );
  });

  test('reports malformed Dart without crashing', () async {
    final fixture = await ProjectFixture.create(files: {
      'lib/broken.dart': 'part missing;\n',
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final audit = await const ProjectAuditor().audit(project);

    expect(audit.unsupportedMarkers, ['lib/broken.dart']);
    expect(audit.isHealthy, isFalse);
  });
}
