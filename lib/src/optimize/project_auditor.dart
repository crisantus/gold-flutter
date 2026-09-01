import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../change/change_plan.dart';
import '../project/project_inspection.dart';

final class ProjectAuditException implements Exception {
  const ProjectAuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ProjectAudit {
  ProjectAudit({
    required Iterable<String> healthyAssets,
    required Iterable<String> missingAssets,
    required Iterable<String> staleGeneratedMarkers,
    Iterable<String> unsupportedMarkers = const [],
  })  : healthyAssets = List.unmodifiable(healthyAssets),
        missingAssets = List.unmodifiable(missingAssets),
        staleGeneratedMarkers = List.unmodifiable(staleGeneratedMarkers),
        unsupportedMarkers = List.unmodifiable(unsupportedMarkers);

  final List<String> healthyAssets;
  final List<String> missingAssets;
  final List<String> staleGeneratedMarkers;
  final List<String> unsupportedMarkers;

  bool get isHealthy =>
      missingAssets.isEmpty &&
      staleGeneratedMarkers.isEmpty &&
      unsupportedMarkers.isEmpty;
}

final class ProjectAuditor {
  const ProjectAuditor();

  Future<ProjectAudit> audit(ProjectInspection project) async {
    final healthyAssets = <String>[];
    final missingAssets = <String>[];
    for (final rawAsset in project.assets) {
      late final String relativeAsset;
      try {
        relativeAsset = ChangePlan.normalizeRelativePath(rawAsset);
      } on ArgumentError {
        throw ProjectAuditException('Unsafe declared asset path: $rawAsset');
      }
      final target = p.joinAll([
        project.root.path,
        ...p.posix.split(relativeAsset),
      ]);
      final reportedAsset = rawAsset.replaceAll('\\', '/').endsWith('/')
          ? '$relativeAsset/'
          : relativeAsset;
      if (await FileSystemEntity.type(target) ==
          FileSystemEntityType.notFound) {
        missingAssets.add(reportedAsset);
      } else {
        healthyAssets.add(reportedAsset);
      }
    }

    final staleMarkers = <String>[];
    final unsupportedMarkers = <String>[];
    final lib = Directory(p.join(project.root.path, 'lib'));
    if (await lib.exists()) {
      await for (final entity in lib.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final source = await entity.readAsString();
        final parsed = parseString(
          content: source,
          path: entity.path,
          throwIfDiagnostics: false,
        );
        if (parsed.errors.isNotEmpty) {
          unsupportedMarkers.add(
            p.posix.joinAll(
              p.split(p.relative(entity.path, from: project.root.path)),
            ),
          );
          continue;
        }
        for (final directive
            in parsed.unit.directives.whereType<PartDirective>()) {
          final uri = directive.uri.stringValue;
          if (uri == null || uri.trim().isEmpty) {
            unsupportedMarkers.add(
              p.posix.joinAll(
                p.split(p.relative(entity.path, from: project.root.path)),
              ),
            );
            continue;
          }
          if (!RegExp(r'\.(?:g|freezed|gr)\.dart$').hasMatch(uri)) {
            continue;
          }
          final generatedPath = p.normalize(p.join(entity.parent.path, uri));
          final relative = p.posix.joinAll(
            p.split(p.relative(generatedPath, from: project.root.path)),
          );
          try {
            ChangePlan.normalizeRelativePath(relative);
          } on ArgumentError {
            unsupportedMarkers.add(relative);
            continue;
          }
          if (!await File(generatedPath).exists()) {
            staleMarkers.add(relative);
          }
        }
      }
    }

    healthyAssets.sort();
    missingAssets.sort();
    staleMarkers.sort();
    unsupportedMarkers.sort();
    return ProjectAudit(
      healthyAssets: healthyAssets,
      missingAssets: missingAssets,
      staleGeneratedMarkers: staleMarkers,
      unsupportedMarkers: unsupportedMarkers,
    );
  }
}
