import 'dart:io';

import 'package:path/path.dart' as p;

import '../change/change_plan.dart';
import '../change/change_report.dart';
import '../change/change_transaction.dart';
import '../process/process_executor.dart';
import '../project/project_inspection.dart';
import '../project/project_inspector.dart';
import 'optimization_detector.dart';
import 'optimization_stage.dart';
import 'project_auditor.dart';

final class OptimizationReport {
  const OptimizationReport({
    required this.transaction,
    required this.audit,
    required this.stages,
  });

  final ChangeReport transaction;
  final ProjectAudit? audit;
  final List<OptimizationStage> stages;

  bool get success => transaction.success && (audit?.isHealthy ?? true);
  bool get restored => transaction.restored;
  String get output => transaction.output;
}

final class ProjectOptimizer {
  const ProjectOptimizer({
    OptimizationDetector detector = const OptimizationDetector(),
    ProjectAuditor auditor = const ProjectAuditor(),
    ChangeTransaction? transaction,
  })  : _detector = detector,
        _auditor = auditor,
        _transaction = transaction;

  final OptimizationDetector _detector;
  final ProjectAuditor _auditor;
  final ChangeTransaction? _transaction;

  Future<ChangePlan> plan(ProjectInspection project) async {
    final stages = await _detector.detect(project);
    final snapshotRoots = <String>[];
    for (final root in const ['lib', 'test', 'pubspec.yaml']) {
      if (await FileSystemEntity.type(p.join(project.root.path, root)) !=
          FileSystemEntityType.notFound) {
        snapshotRoots.add(root);
      }
    }
    // pub get may create the lockfile, so record both its present and absent
    // state to make rollback complete.
    snapshotRoots.add('pubspec.lock');
    return ChangePlan(
      summary: 'Optimize ${project.projectName}',
      projectRoot: project.root,
      commands: [
        for (final stage in stages)
          PlannedCommand(
            executable: stage.executable,
            arguments: stage.arguments,
            reason: _reason(stage.kind),
            mutatesFiles: stage.mutatesFiles,
          ),
      ],
      snapshotRoots: snapshotRoots,
    );
  }

  Future<OptimizationReport> run(ChangePlan plan) async {
    final transaction = _transaction ??
        ChangeTransaction(executor: const LocalProcessExecutor());
    final stages = [
      for (final command in plan.commands)
        OptimizationStage(
          kind: _kind(command),
          executable: command.executable,
          arguments: command.arguments,
          mutatesFiles: command.mutatesFiles,
        ),
    ];
    final report = await transaction.execute(plan);
    final audit = report.success
        ? await _auditor.audit(
            ProjectInspection(
              root: plan.projectRoot,
              projectName: plan.summary.replaceFirst('Optimize ', ''),
              dependencies: const {},
              assets: await _readAssets(plan.projectRoot),
              hasTests: await Directory(p.join(plan.projectRoot.path, 'test'))
                  .exists(),
              hasGit: false,
              isDirty: false,
            ),
          )
        : null;
    return OptimizationReport(
      transaction: report,
      audit: audit,
      stages: List.unmodifiable(stages),
    );
  }

  static String _reason(OptimizationStageKind kind) => switch (kind) {
        OptimizationStageKind.pubGet => 'Resolve Flutter dependencies.',
        OptimizationStageKind.buildRunner => 'Regenerate declared source.',
        OptimizationStageKind.format => 'Format Dart source.',
        OptimizationStageKind.analyze => 'Analyze the Flutter project.',
        OptimizationStageKind.test => 'Run the Flutter test suite.',
      };

  static OptimizationStageKind _kind(PlannedCommand command) {
    final value = [command.executable, ...command.arguments].join(' ');
    if (value == 'flutter pub get') return OptimizationStageKind.pubGet;
    if (value.startsWith('dart run build_runner')) {
      return OptimizationStageKind.buildRunner;
    }
    if (value.startsWith('dart format')) return OptimizationStageKind.format;
    if (value == 'flutter analyze') return OptimizationStageKind.analyze;
    return OptimizationStageKind.test;
  }

  static Future<List<String>> _readAssets(Directory root) async {
    final project = await const ProjectInspector().inspect(root);
    return project.assets;
  }
}
