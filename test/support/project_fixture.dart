import 'dart:io';

import 'package:path/path.dart' as p;

final class ProjectFixture {
  ProjectFixture._(this.root);

  final Directory root;

  static Future<ProjectFixture> create({
    Map<String, String> files = const {},
  }) async {
    final root = await Directory.systemTemp.createTemp('gold_project_');
    final fixture = ProjectFixture._(root);
    await fixture.write(
      'pubspec.yaml',
      'name: fixture\nenvironment:\n  sdk: ">=3.5.0 <4.0.0"\n'
          'dependencies:\n  flutter:\n    sdk: flutter\n',
    );
    for (final entry in files.entries) {
      await fixture.write(entry.key, entry.value);
    }
    return fixture;
  }

  File file(String relativePath) => File(_validatedPath(relativePath));

  Future<void> write(String relativePath, String content) async {
    final target = file(relativePath);
    await target.parent.create(recursive: true);
    await target.writeAsString(content);
  }

  Future<void> dispose() => root.delete(recursive: true);

  String _validatedPath(String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must be a relative path within the fixture root',
      );
    }

    final rootPath = p.normalize(root.path);
    final targetPath = p.normalize(p.join(rootPath, relativePath));
    final pathFromRoot = p.relative(targetPath, from: rootPath);
    if (pathFromRoot == '..' || pathFromRoot.startsWith('..${p.separator}')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must remain within the fixture root',
      );
    }
    return targetPath;
  }
}
