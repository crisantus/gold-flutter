# Developer Assistant Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the safe project-inspection, change-planning, preview, confirmation, and rollback foundation used by every Gold Flutter 0.2.0 project-assistant command.

**Architecture:** A `ProjectInspector` produces immutable local project metadata. Commands build a `ChangePlan`; a presenter prints it, and a `ChangeTransaction` snapshots only named paths before applying file writes or delegated operations. The transaction restores those paths on failure without invoking destructive Git commands.

**Tech Stack:** Dart 3.5+, `args`, `path`, `yaml`, `dart:io`, package:test

**Spec:** `docs/superpowers/specs/2026-08-31-developer-assistant-design.md`

## Global Constraints

- Version under development is exactly `0.2.0-dev`.
- No AI, offline mode, module registry, or project-specific feature scaffolds.
- `--dry-run` never writes files or starts mutating subprocesses.
- `--yes` skips confirmation but never suppresses failures.
- Writes must remain inside the inspected Flutter project root.
- Existing dirty Git files outside an approved plan are never changed or restored.
- Use `apply_patch` for repository source edits and TDD for every behavior.

## File map

- Create `lib/src/project/project_inspection.dart`: immutable project metadata.
- Create `lib/src/project/project_inspector.dart`: Flutter-root and Git inspection.
- Create `lib/src/change/change_plan.dart`: planned file and subprocess operations.
- Create `lib/src/change/change_report.dart`: execution result and terminal facts.
- Create `lib/src/change/project_file_system.dart`: injectable scoped file operations.
- Create `lib/src/change/change_transaction.dart`: scoped snapshots, writes, rollback.
- Create `lib/src/change/change_plan_presenter.dart`: preview and confirmation output.
- Create `test/support/project_fixture.dart`: disposable Flutter project fixture.
- Create unit tests mirroring each production file under `test/unit/`.
- Modify `pubspec.yaml`, `lib/src/cli/gold_flutter_cli.dart`, and its test for version/help text only.

---

### Task 1: Version and disposable Flutter project fixture

**Files:**
- Modify: `pubspec.yaml:1-6`
- Modify: `lib/src/cli/gold_flutter_cli.dart:15-25`
- Modify: `test/unit/cli/gold_flutter_cli_test.dart:10-20`
- Create: `test/support/project_fixture.dart`

**Interfaces:**
- Produces: `Future<ProjectFixture> ProjectFixture.create({Map<String, String> files = const {}})`
- Produces: `Directory ProjectFixture.root`, `File ProjectFixture.file(String relativePath)`, and `Future<void> ProjectFixture.dispose()`

- [ ] **Step 1: Change the CLI version expectation first**

```dart
expect(io.output.single, contains('0.2.0-dev'));
```

- [ ] **Step 2: Run the focused test and observe the old version failure**

Run: `dart test test/unit/cli/gold_flutter_cli_test.dart --name version`

Expected: FAIL because output still contains `0.1.0`.

- [ ] **Step 3: Set both package and CLI versions to `0.2.0-dev`**

```yaml
version: 0.2.0-dev
```

```dart
static const version = '0.2.0-dev';
```

- [ ] **Step 4: Add the disposable project fixture**

```dart
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

  File file(String relativePath) => File(p.join(root.path, relativePath));

  Future<void> write(String relativePath, String content) async {
    final target = file(relativePath);
    await target.parent.create(recursive: true);
    await target.writeAsString(content);
  }

  Future<void> dispose() => root.delete(recursive: true);
}
```

- [ ] **Step 5: Format and verify**

Run: `dart format lib test && dart test test/unit/cli/gold_flutter_cli_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/src/cli/gold_flutter_cli.dart \
  test/unit/cli/gold_flutter_cli_test.dart test/support/project_fixture.dart
git commit -m "chore: begin gold flutter 0.2 development"
```

### Task 2: Inspect Flutter projects safely

**Files:**
- Create: `lib/src/project/project_inspection.dart`
- Create: `lib/src/project/project_inspector.dart`
- Create: `test/unit/project/project_inspector_test.dart`

**Interfaces:**
- Produces: `ProjectInspection(root, projectName, dependencies, assets, hasTests, hasGit, isDirty)`
- Produces: `Future<ProjectInspection> ProjectInspector.inspect(Directory start)`
- Produces: `const ProjectInspector({ProcessExecutor executor = const LocalProcessExecutor()})`
- Throws: `ProjectInspectionException` with a user-facing `message`

- [ ] **Step 1: Write tests for root discovery, metadata, and rejection**

```dart
test('walks upward and reads Flutter project metadata', () async {
  final fixture = await ProjectFixture.create(files: {
    'pubspec.yaml': '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.4.2
flutter:
  assets:
    - assets/images/
''',
    'lib/features/example.dart': '',
    'test/widget_test.dart': '',
  });
  addTearDown(fixture.dispose);

  final result = await const ProjectInspector().inspect(
    Directory(p.join(fixture.root.path, 'lib/features')),
  );

  expect(result.root.path, fixture.root.path);
  expect(result.projectName, 'sample_app');
  expect(result.dependencies, contains('flutter_riverpod'));
  expect(result.assets, ['assets/images/']);
  expect(result.hasTests, isTrue);
});

test('rejects a directory outside a Flutter project', () async {
  final root = await Directory.systemTemp.createTemp('gold_not_flutter_');
  addTearDown(() => root.delete(recursive: true));
  expect(
    () => const ProjectInspector().inspect(root),
    throwsA(isA<ProjectInspectionException>()),
  );
});
```

- [ ] **Step 2: Run the test and verify missing-type failures**

Run: `dart test test/unit/project/project_inspector_test.dart`

Expected: FAIL because the inspector types do not exist.

- [ ] **Step 3: Implement immutable metadata**

```dart
final class ProjectInspection {
  ProjectInspection({
    required this.root,
    required this.projectName,
    required Set<String> dependencies,
    required List<String> assets,
    required this.hasTests,
    required this.hasGit,
    required this.isDirty,
  })  : dependencies = Set.unmodifiable(dependencies),
        assets = List.unmodifiable(assets);

  final Directory root;
  final String projectName;
  final Set<String> dependencies;
  final List<String> assets;
  final bool hasTests;
  final bool hasGit;
  final bool isDirty;
}
```

- [ ] **Step 4: Implement upward discovery and YAML parsing**

Use `p.equals(parent.path, candidate.path)` as the filesystem-root stop
condition. Accept a pubspec only when `dependencies.flutter.sdk == 'flutter'`.
Collect dependency keys from dependencies and dev_dependencies. Parse Flutter
assets as strings. Use `git status --porcelain` through `ProcessExecutor` only
when `.git` exists; a failed Git check sets `hasGit` false instead of blocking
non-Git Flutter projects.

- [ ] **Step 5: Run focused and full tests**

Run: `dart test test/unit/project/project_inspector_test.dart && dart test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/project test/unit/project
git commit -m "feat: inspect existing flutter projects"
```

### Task 3: Represent and validate change plans

**Files:**
- Create: `lib/src/change/change_plan.dart`
- Create: `test/unit/change/change_plan_test.dart`

**Interfaces:**
- Produces: `enum FileChangeKind { create, modify }`
- Produces: `PlannedFileChange(relativePath, content, kind, reason)`
- Produces: `PlannedCommand(executable, arguments, reason, mutatesFiles)`
- Produces: `ChangePlan(summary, projectRoot, files, commands, snapshotRoots)`

- [ ] **Step 1: Write containment and conflict tests**

```dart
test('rejects duplicate and escaping paths', () {
  final root = Directory('/work/app');
  expect(
    () => ChangePlan(
      summary: 'unsafe',
      projectRoot: root,
      files: const [
        PlannedFileChange(
          relativePath: '../outside.dart',
          content: '',
          kind: FileChangeKind.create,
          reason: 'invalid',
        ),
      ],
    ),
    throwsArgumentError,
  );
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `dart test test/unit/change/change_plan_test.dart`

Expected: FAIL because plan types do not exist.

- [ ] **Step 3: Implement immutable plan types and validation**

Normalize each relative path with `p.normalize`, reject absolute paths and any
normalized path equal to `..` or starting with `../`, and reject duplicates.
Expose unmodifiable lists. `snapshotRoots` uses the same containment checks.

- [ ] **Step 4: Test immutability and valid ordering**

Add expectations that create/modify order remains stable and returned lists
cannot be mutated.

- [ ] **Step 5: Run and commit**

Run: `dart test test/unit/change/change_plan_test.dart`

```bash
git add lib/src/change/change_plan.dart test/unit/change/change_plan_test.dart
git commit -m "feat: model safe project change plans"
```

### Task 4: Apply and roll back scoped transactions

**Files:**
- Create: `lib/src/change/change_report.dart`
- Create: `lib/src/change/project_file_system.dart`
- Create: `lib/src/change/change_transaction.dart`
- Create: `test/unit/change/change_transaction_test.dart`

**Interfaces:**
- Consumes: `ChangePlan`, `ProcessExecutor`
- Consumes: injectable `ProjectFileSystem` for deterministic restoration tests.
- Produces: `Future<ChangeReport> ChangeTransaction.execute(ChangePlan plan)`
- Produces: `ChangeReport(success, restored, created, modified, skipped, output)`

- [ ] **Step 1: Write create/modify success and command-failure rollback tests**

```dart
test('restores modified files and removes created files after failure', () async {
  final fixture = await ProjectFixture.create(files: {'lib/existing.dart': 'old'});
  addTearDown(fixture.dispose);
  final executor = FakeProcessExecutor({
    'flutter analyze': const ProcessOutput(
      exitCode: 1,
      stdout: '',
      stderr: 'analysis failed',
    ),
  });
  final plan = ChangePlan(
    summary: 'rollback example',
    projectRoot: fixture.root,
    files: const [
      PlannedFileChange(
        relativePath: 'lib/existing.dart',
        content: 'new',
        kind: FileChangeKind.modify,
        reason: 'arrange model',
      ),
      PlannedFileChange(
        relativePath: 'lib/created.dart',
        content: 'created',
        kind: FileChangeKind.create,
        reason: 'new helper',
      ),
    ],
    commands: const [
      PlannedCommand(
        executable: 'flutter',
        arguments: ['analyze'],
        reason: 'verify',
        mutatesFiles: false,
      ),
    ],
  );

  final report = await ChangeTransaction(executor: executor).execute(plan);

  expect(report.success, isFalse);
  expect(report.restored, isTrue);
  expect(fixture.file('lib/existing.dart').readAsStringSync(), 'old');
  expect(fixture.file('lib/created.dart').existsSync(), isFalse);
});
```

- [ ] **Step 2: Run the test and observe failure**

Run: `dart test test/unit/change/change_transaction_test.dart`

Expected: FAIL because transaction types do not exist.

- [ ] **Step 3: Implement snapshots and atomic file writes**

Define this adapter and a `LocalProjectFileSystem` implementation:

```dart
abstract interface class ProjectFileSystem {
  Future<bool> exists(String path);
  Future<List<int>> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> delete(String path);
  Future<void> copyTree(String source, String destination);
}
```

Create a temporary snapshot directory with `Directory.systemTemp.createTemp`.
Copy named files and recursively copy named snapshot roots before the first
write. Write each file through a sibling temporary file followed by `rename`.
Run planned commands sequentially and stop on the first nonzero exit code.

- [ ] **Step 4: Implement restoration in `finally`**

On failure, restore original bytes, remove transaction-created paths, then
delete only the transaction's temporary directory. On success, delete the
snapshot without restoration. Capture stdout and stderr in command order.

- [ ] **Step 5: Cover a failed restoration without hiding the root failure**

Inject a filesystem adapter whose restore write throws. Assert
`report.success == false`, `report.restored == false`, and output contains both
`analysis failed` and `restore failed`.

- [ ] **Step 6: Run and commit**

Run: `dart test test/unit/change/change_transaction_test.dart && dart test`

```bash
git add lib/src/change/change_report.dart \
  lib/src/change/project_file_system.dart lib/src/change/change_transaction.dart \
  test/unit/change/change_transaction_test.dart
git commit -m "feat: apply project changes transactionally"
```

### Task 5: Present plans and confirm interactive changes

**Files:**
- Create: `lib/src/change/change_plan_presenter.dart`
- Create: `test/unit/change/change_plan_presenter_test.dart`

**Interfaces:**
- Consumes: `PromptIO`, `ChangePlan`
- Produces: `void ChangePlanPresenter.print(ChangePlan plan)`
- Produces: `bool ChangePlanPresenter.confirm({required bool assumeYes, required bool dryRun})`

- [ ] **Step 1: Write output and confirmation tests**

```dart
test('dry run prints files and never consumes confirmation input', () {
  final io = FakePromptIO(['yes']);
  final presenter = ChangePlanPresenter(io: io);
  presenter.print(plan);
  expect(presenter.confirm(assumeYes: false, dryRun: true), isFalse);
  expect(io.output.join('\n'), contains('No files have been changed.'));
  expect(io.prompts, isEmpty);
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `dart test test/unit/change/change_plan_presenter_test.dart`

- [ ] **Step 3: Implement stable terminal sections**

Print `Create`, `Modify`, `Run`, and `Snapshot` headings only when populated.
For interactive confirmation, accept `y`, `yes`, empty-as-yes, `n`, and `no`;
repeat after other input. `assumeYes` returns true without reading input.

- [ ] **Step 4: Run the core suite**

Run: `dart format lib test && dart analyze && dart test`

Expected: formatting unchanged after the first format, no analyzer issues, all
tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/src/change/change_plan_presenter.dart \
  test/unit/change/change_plan_presenter_test.dart
git commit -m "feat: preview and confirm project changes"
```
