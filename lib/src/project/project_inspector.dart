import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../process/process_executor.dart';
import 'project_inspection.dart';

final class ProjectInspectionException implements Exception {
  const ProjectInspectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ProjectInspector {
  const ProjectInspector(
      {ProcessExecutor executor = const LocalProcessExecutor()})
      : _executor = executor;

  final ProcessExecutor _executor;

  Future<ProjectInspection> inspect(Directory start) async {
    final root = await _findFlutterProjectRoot(start);
    final pubspec = await _readPubspec(root);
    final gitStatus = await _gitStatus(root);

    return ProjectInspection(
      root: root,
      projectName: pubspec['name'] as String? ?? root.uri.pathSegments.last,
      dependencies: _dependencyNames(pubspec),
      assets: _assetPaths(pubspec),
      hasTests: await Directory(p.join(root.path, 'test')).exists(),
      hasGit: gitStatus.hasGit,
      isDirty: gitStatus.isDirty,
    );
  }

  Future<Directory> _findFlutterProjectRoot(Directory start) async {
    var candidate = start.absolute;
    while (true) {
      final pubspec = await _tryReadFlutterPubspec(candidate);
      if (pubspec != null) {
        return candidate;
      }

      final parent = candidate.parent;
      if (p.equals(parent.path, candidate.path)) {
        throw const ProjectInspectionException(
          'No Flutter project was found above this directory.',
        );
      }
      candidate = parent;
    }
  }

  Future<YamlMap> _readPubspec(Directory root) async {
    final pubspec = await _tryReadFlutterPubspec(root);
    if (pubspec == null) {
      throw const ProjectInspectionException(
        'The selected directory is not a Flutter project.',
      );
    }
    return pubspec;
  }

  Future<YamlMap?> _tryReadFlutterPubspec(Directory root) async {
    final file = File(p.join(root.path, 'pubspec.yaml'));
    if (!await file.exists()) {
      return null;
    }

    try {
      final parsed = loadYaml(await file.readAsString());
      if (parsed is! YamlMap || parsed['dependencies'] is! YamlMap) {
        return null;
      }
      final flutter = (parsed['dependencies'] as YamlMap)['flutter'];
      if (flutter is! YamlMap || flutter['sdk'] != 'flutter') {
        return null;
      }
      return parsed;
    } on YamlException {
      return null;
    }
  }

  Set<String> _dependencyNames(YamlMap pubspec) {
    return {
      ..._keysOf(pubspec['dependencies']),
      ..._keysOf(pubspec['dev_dependencies']),
    };
  }

  Set<String> _keysOf(Object? value) {
    if (value is! YamlMap) {
      return const {};
    }
    return value.keys.whereType<String>().toSet();
  }

  List<String> _assetPaths(YamlMap pubspec) {
    final flutter = pubspec['flutter'];
    if (flutter is! YamlMap || flutter['assets'] is! YamlList) {
      return const [];
    }
    return (flutter['assets'] as YamlList).whereType<String>().toList();
  }

  Future<_GitStatus> _gitStatus(Directory root) async {
    final gitEntry = await FileSystemEntity.type(p.join(root.path, '.git'));
    if (gitEntry == FileSystemEntityType.notFound) {
      return const _GitStatus.notAvailable();
    }

    try {
      final result = await _executor.run(
        'git',
        const ['status', '--porcelain'],
        workingDirectory: root,
      );
      if (result.exitCode != 0) {
        return const _GitStatus.notAvailable();
      }
      return _GitStatus(
          available: true, dirty: result.stdout.trim().isNotEmpty);
    } catch (_) {
      return const _GitStatus.notAvailable();
    }
  }
}

final class _GitStatus {
  const _GitStatus({required this.available, required this.dirty});

  const _GitStatus.notAvailable()
      : available = false,
        dirty = false;

  final bool available;
  final bool dirty;

  bool get hasGit => available;
  bool get isDirty => dirty;
}
