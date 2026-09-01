import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

final class GoldFlutterTestFixtures {
  GoldFlutterTestFixtures._(this._fixtureRoot);

  final Directory _fixtureRoot;

  static Future<GoldFlutterTestFixtures> resolve() async {
    final libraryUri = await Isolate.resolvePackageUri(
      Uri.parse('package:gold_flutter/gold_flutter.dart'),
    );
    if (libraryUri == null || libraryUri.scheme != 'file') {
      throw StateError('Unable to resolve the gold_flutter package root.');
    }
    final packageRoot = File.fromUri(libraryUri).parent.parent;
    return GoldFlutterTestFixtures._(
      Directory(p.join(packageRoot.path, 'test', 'fixtures')),
    );
  }

  String readAsString(String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must be relative to test/fixtures',
      );
    }
    final rootPath = p.normalize(_fixtureRoot.path);
    final fixturePath = p.normalize(p.join(rootPath, relativePath));
    if (!p.isWithin(rootPath, fixturePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must remain inside test/fixtures',
      );
    }
    return File(fixturePath).readAsStringSync();
  }
}
