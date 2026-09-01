import 'package:gold_flutter/src/docs/project_documentation_scanner.dart';
import 'package:gold_flutter/src/project/project_inspector.dart';
import 'package:test/test.dart';

import '../../support/project_fixture.dart';

void main() {
  test('scans dependencies assets models and literal AutoRoute facts',
      () async {
    final fixture = await ProjectFixture.create(files: {
      'pubspec.yaml': '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.0.0
  auto_route: ^10.0.0
flutter:
  assets:
    - assets/images/
''',
      'lib/domain/models/user_model.dart': '''
class UserModel {
  final String id;
  final int age;
  UserModel({required this.id, required this.age});
}
''',
      'lib/core/route/app_router.dart': '''
@AutoRouterConfig()
class AppRouter {
  final routes = [
    AutoRoute(page: HomeRoute.page, path: '/', initial: true),
    AutoRoute(page: ProfileRoute.page),
  ];
}
''',
      'assets/images/.keep': '',
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final snapshot = await const ProjectDocumentationScanner().scan(project);

    expect(snapshot.projectName, 'sample_app');
    expect(
        snapshot.dependencies, containsAll(['auto_route', 'flutter_riverpod']));
    expect(snapshot.assets, ['assets/images/']);
    expect(snapshot.models.single.name, 'UserModel');
    expect(snapshot.models.single.fields.map((field) => field.name),
        ['id', 'age']);
    expect(snapshot.routes.map((route) => route.name),
        ['HomeRoute', 'ProfileRoute']);
    expect(snapshot.routes.first.path, '/');
    expect(snapshot.routes.first.isInitial, isTrue);
  });

  test('records malformed source as unknown instead of inventing facts',
      () async {
    final fixture = await ProjectFixture.create(files: {
      'lib/domain/models/broken.dart': 'class {',
    });
    addTearDown(fixture.dispose);
    final project = await const ProjectInspector().inspect(fixture.root);

    final snapshot = await const ProjectDocumentationScanner().scan(project);

    expect(snapshot.models, isEmpty);
    expect(snapshot.unknownFacts.join('\n'), contains('broken.dart'));
  });
}
