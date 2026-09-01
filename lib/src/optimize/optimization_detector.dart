import 'dart:io';

import 'package:path/path.dart' as p;

import '../project/project_inspection.dart';
import 'optimization_stage.dart';

final class OptimizationDetector {
  const OptimizationDetector();

  Future<List<OptimizationStage>> detect(ProjectInspection project) async {
    final hasLib = await Directory(p.join(project.root.path, 'lib')).exists();
    final hasTest = await Directory(p.join(project.root.path, 'test')).exists();
    final stages = <OptimizationStage>[
      OptimizationStage(
        kind: OptimizationStageKind.pubGet,
        executable: 'flutter',
        arguments: const ['pub', 'get'],
        mutatesFiles: true,
      ),
    ];

    if (project.dependencies.contains('build_runner') &&
        await _hasGeneratedMarker(project.root)) {
      stages.add(
        OptimizationStage(
          kind: OptimizationStageKind.buildRunner,
          executable: 'dart',
          arguments: const [
            'run',
            'build_runner',
            'build',
            '--delete-conflicting-outputs',
          ],
          mutatesFiles: true,
        ),
      );
    }

    final formatTargets = <String>[
      if (hasLib) 'lib',
      if (hasTest) 'test',
    ];
    if (formatTargets.isNotEmpty) {
      stages.add(
        OptimizationStage(
          kind: OptimizationStageKind.format,
          executable: 'dart',
          arguments: ['format', ...formatTargets],
          mutatesFiles: true,
        ),
      );
    }
    stages.add(
      OptimizationStage(
        kind: OptimizationStageKind.analyze,
        executable: 'flutter',
        arguments: const ['analyze'],
        mutatesFiles: false,
      ),
    );
    if (hasTest) {
      stages.add(
        OptimizationStage(
          kind: OptimizationStageKind.test,
          executable: 'flutter',
          arguments: const ['test'],
          mutatesFiles: false,
        ),
      );
    }
    return List.unmodifiable(stages);
  }

  Future<bool> _hasGeneratedMarker(Directory root) async {
    for (final directoryName in const ['lib', 'test']) {
      final directory = Directory(p.join(root.path, directoryName));
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final source = await entity.readAsString();
        if (RegExp(
          r'''\bpart\s+['"][^'"]+\.(?:g|freezed|gr)\.dart['"]\s*;''',
        ).hasMatch(source)) {
          return true;
        }
      }
    }
    return false;
  }
}
