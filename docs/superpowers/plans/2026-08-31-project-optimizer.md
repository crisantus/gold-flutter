# Project Optimizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `gold_flutter optimize` as a transparent Flutter project-health pipeline with dry-run planning, early failure, asset checks, and scoped rollback.

**Architecture:** An optimizer detector builds an ordered stage list from inspected project metadata and local source markers. The shared transaction snapshots source roots, runs Flutter/Dart commands sequentially, and restores source changes after failure. A read-only asset and generated-source audit enriches the final report.

**Tech Stack:** Dart 3.5+, `yaml`, `path`, shared `ProjectInspector`, `ChangePlan`, `ChangeTransaction`, and `ProcessExecutor`

**Spec:** `docs/superpowers/specs/2026-08-31-developer-assistant-design.md`

## Global Constraints

- Complete `2026-08-31-developer-assistant-core.md` and
  `2026-08-31-eyeask-model-arranger.md` first so analyzer is available.
- Optimize means project-health verification, not runtime-performance tuning.
- Stage order is pub get, conditional build runner, format, analyze, test, audit.
- Stop after the first failing subprocess.
- Never remove dependencies or rewrite application business logic.
- Snapshot `lib`, `test`, `pubspec.yaml`, and `pubspec.lock` before mutating stages.
- Package downloads and external caches are not rolled back.

## File map

- Create `lib/src/optimize/optimization_stage.dart`: typed stage definition.
- Create `lib/src/optimize/optimization_detector.dart`: stage selection.
- Create `lib/src/optimize/project_auditor.dart`: assets and generated markers.
- Create `lib/src/optimize/project_optimizer.dart`: change plan and final report.
- Create tests under `test/unit/optimize/`.
- Modify CLI and README.

---

### Task 1: Detect the exact optimization stages

**Files:**
- Create: `lib/src/optimize/optimization_stage.dart`
- Create: `lib/src/optimize/optimization_detector.dart`
- Create: `test/unit/optimize/optimization_detector_test.dart`

**Interfaces:**
- Produces: `enum OptimizationStageKind { pubGet, buildRunner, format, analyze, test }`
- Produces: `OptimizationStage(kind, executable, arguments, mutatesFiles)`
- Produces: `Future<List<OptimizationStage>> OptimizationDetector.detect(ProjectInspection project)`

- [ ] **Step 1: Write stage-order tests**

```dart
test('includes build runner only when declared and referenced', () async {
  final fixture = await ProjectFixture.create(files: {
    'pubspec.yaml': '''
name: sample
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.0.0
  auto_route_generator: ^10.0.0
''',
    'lib/core/route/app_router.dart': "part 'app_router.gr.dart';",
    'test/widget_test.dart': '',
  });
  addTearDown(fixture.dispose);
  final project = await const ProjectInspector().inspect(fixture.root);
  final stages = await const OptimizationDetector().detect(project);
  expect(stages.map((item) => item.kind), [
    OptimizationStageKind.pubGet,
    OptimizationStageKind.buildRunner,
    OptimizationStageKind.format,
    OptimizationStageKind.analyze,
    OptimizationStageKind.test,
  ]);
});
```

Add cases without build runner, without `test/`, and without `lib/`.

- [ ] **Step 2: Run and observe failure**

Run: `dart test test/unit/optimize/optimization_detector_test.dart`

- [ ] **Step 3: Implement immutable stages**

Use these exact commands:

```text
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format lib test              # omit missing paths
flutter analyze
flutter test                      # omit when test/ is missing
```

Detect generated code by scanning Dart files for `part` directives ending in
`.g.dart`, `.freezed.dart`, or `.gr.dart`; use Dart source line inspection only
for this marker check, not for model parsing.

- [ ] **Step 4: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/optimize/optimization_detector_test.dart`

```bash
git add lib/src/optimize/optimization_stage.dart \
  lib/src/optimize/optimization_detector.dart \
  test/unit/optimize/optimization_detector_test.dart
git commit -m "feat: detect flutter optimization stages"
```

### Task 2: Audit declared assets and generated source

**Files:**
- Create: `lib/src/optimize/project_auditor.dart`
- Create: `test/unit/optimize/project_auditor_test.dart`

**Interfaces:**
- Produces: `ProjectAudit(healthyAssets, missingAssets, staleGeneratedMarkers)`
- Produces: `Future<ProjectAudit> ProjectAuditor.audit(ProjectInspection project)`

- [ ] **Step 1: Write asset and marker tests**

Create a fixture declaring one existing asset directory and one missing file.
Add `part 'missing.gr.dart';` with no matching file. Assert both missing paths
are reported relative to project root and existing paths are not.

- [ ] **Step 2: Run and observe failure**

Run: `dart test test/unit/optimize/project_auditor_test.dart`

- [ ] **Step 3: Implement read-only audit**

Resolve each asset path under project root and reject traversal. A declared
directory is healthy when it exists, even when empty. Parse Dart files with
analyzer `parseString` and inspect `PartDirective` URIs; report a marker only
when its resolved file does not exist.

- [ ] **Step 4: Test malformed pubspec and invalid part URIs**

Malformed project metadata throws `ProjectAuditException`; dynamic/non-string
part URIs are reported as unsupported without crashing.

- [ ] **Step 5: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/optimize/project_auditor_test.dart`

```bash
git add lib/src/optimize/project_auditor.dart \
  test/unit/optimize/project_auditor_test.dart
git commit -m "feat: audit flutter assets and generated files"
```

### Task 3: Execute optimization transactionally

**Files:**
- Create: `lib/src/optimize/project_optimizer.dart`
- Create: `test/unit/optimize/project_optimizer_test.dart`

**Interfaces:**
- Consumes: detector, auditor, transaction.
- Produces: `Future<ChangePlan> ProjectOptimizer.plan(ProjectInspection project)`.
- Produces: `Future<OptimizationReport> ProjectOptimizer.run(ChangePlan plan)`.

- [ ] **Step 1: Write exact plan and early-failure tests**

Assert the plan contains stage commands in detector order and snapshot roots
`lib`, `test`, `pubspec.yaml`, and `pubspec.lock` only when each exists. Use a
fake executor whose analyze stage fails; assert test is never called and source
files modified by the fake format stage are restored.

- [ ] **Step 2: Run and observe failure**

Run: `dart test test/unit/optimize/project_optimizer_test.dart`

- [ ] **Step 3: Implement plan construction**

Convert each stage into `PlannedCommand` preserving `mutatesFiles`. The plan has
no direct file changes, summary `Optimize ${project.projectName}`, and snapshot
roots derived from existing paths.

- [ ] **Step 4: Implement the final report**

On transaction success, run the read-only auditor and print completed stages,
missing assets, and stale generated markers. Missing assets/markers make the
report unhealthy and exit code 1 but do not trigger rollback because the tool
stages completed correctly and the audit is advisory. A subprocess failure
triggers rollback and includes captured stderr.

- [ ] **Step 5: Test dry-run behavior**

Assert plan creation performs filesystem reads only and neither executor nor
auditor runs when the CLI selects `--dry-run`.

- [ ] **Step 6: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/optimize`

```bash
git add lib/src/optimize/project_optimizer.dart \
  test/unit/optimize/project_optimizer_test.dart
git commit -m "feat: optimize flutter projects safely"
```

### Task 4: Wire CLI, help, docs, and integration coverage

**Files:**
- Modify: `lib/src/cli/gold_flutter_cli.dart`
- Modify: `test/unit/cli/gold_flutter_cli_test.dart`
- Create: `test/integration/optimize_command_test.dart`
- Modify: `README.md`

**Interfaces:**
- Produces CLI: `gold_flutter optimize [--dry-run] [--yes]`.

- [ ] **Step 1: Add failing help and delegation tests**

Assert `optimize --help` lists both flags, `--dry-run` prints all detected
stages, and `--yes` does not read prompt input.

- [ ] **Step 2: Run and observe command-not-found failures**

Run: `dart test test/unit/cli/gold_flutter_cli_test.dart --name optimize`

- [ ] **Step 3: Wire injected optimizer dependencies**

Inspect `_currentDirectory`, print the plan with `ChangePlanPresenter`, return 0
for a healthy report, 1 for subprocess/audit failure, and 64 for a non-Flutter
directory or invalid option.

- [ ] **Step 4: Add integration coverage**

Use a disposable fixture and fake executor. Assert calls exactly equal:

```dart
[
  'flutter pub get',
  'dart format lib test',
  'flutter analyze',
  'flutter test',
]
```

- [ ] **Step 5: Document precise meaning and limitations**

State that optimize checks project health, may format and regenerate source,
stops on failure, allows internet, and does not tune runtime performance.

- [ ] **Step 6: Verify and commit**

Run: `dart format --output=none --set-exit-if-changed bin lib test && dart analyze && dart test`

```bash
git add lib/src/cli/gold_flutter_cli.dart test/unit/cli/gold_flutter_cli_test.dart \
  test/integration/optimize_command_test.dart README.md
git commit -m "feat: add flutter project optimizer command"
```
