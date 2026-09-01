import 'package:gold_flutter/src/docs/project_documentation.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes set-like documentation facts in stable order', () {
    final snapshot = ProjectDocumentation.normalized(
      projectName: 'sample',
      dependencies: {'yaml', 'args'},
      assets: {'assets/images/', 'assets/icons/'},
      layers: {'presentation', 'core'},
      routes: const [],
      models: const [],
      unknownFacts: const [],
      generatedAtVersion: '0.2.0-dev',
    );

    expect(snapshot.dependencies, ['args', 'yaml']);
    expect(snapshot.assets, ['assets/icons/', 'assets/images/']);
    expect(snapshot.layers, ['core', 'presentation']);
  });
}
