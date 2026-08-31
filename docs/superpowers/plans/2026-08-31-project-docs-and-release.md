# Project Documentation and 0.2.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `gold_flutter docs`, complete public command documentation and CI smoke coverage, then prepare the verified `0.2.0` release candidate.

**Architecture:** Focused scanners produce an immutable documentation snapshot from pubspec, assets, Dart models, and AutoRoute declarations. A Markdown renderer writes only Gold Flutter-owned documentation tracked by a JSON hash manifest, preserving user edits. Final integration tests exercise all 0.2.0 commands before branch installation and release review.

**Tech Stack:** Dart 3.5+, analyzer AST, `yaml`, `dart:convert`, `crypto`, GitHub Actions, shared Developer Assistant Core

**Spec:** `docs/superpowers/specs/2026-08-31-developer-assistant-design.md`

## Global Constraints

- Complete the core, model arranger, optimizer, and amount formatter plans first.
- Generate Markdown only from discoverable local facts; never invent feature descriptions.
- Write generated documentation under `docs/gold_flutter/` only.
- Preserve user-modified generated files by comparing their current hash with the previous ownership manifest.
- The repository README documents stable and feature-branch installation.
- Release only after local tests, generated-project tests, independent review, public branch installation, and hosted CI pass.
- Do not merge, tag, or delete a branch without the user's explicit integration choice.

## File map

- Create `lib/src/docs/project_documentation.dart`: immutable snapshot models.
- Create `lib/src/docs/project_documentation_scanner.dart`: pubspec/assets/source scan.
- Create `lib/src/docs/markdown_documentation_renderer.dart`: seven Markdown files.
- Create `lib/src/docs/documentation_manifest.dart`: owned hashes and update checks.
- Create `lib/src/docs/documentation_generator.dart`: change-plan orchestration.
- Create tests under `test/unit/docs/` and `test/integration/`.
- Modify CLI, README, CONTRIBUTING, CHANGELOG, and CI.

---

### Task 1: Add hash support and documentation snapshot types

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/src/docs/project_documentation.dart`
- Create: `test/unit/docs/project_documentation_test.dart`

**Interfaces:**
- Produces: `ProjectDocumentation(projectName, dependencies, assets, routes, models, generatedAtVersion)`.
- Produces: `RouteDocumentation(name, path, isInitial)` and `ModelDocumentation(name, fields)`.

- [ ] **Step 1: Write immutability and stable-order tests**

```dart
test('documentation snapshot stores stable sorted facts', () {
  final snapshot = ProjectDocumentation.normalized(
    projectName: 'sample',
    dependencies: {'yaml', 'args'},
    assets: {'assets/images/', 'assets/icons/'},
    routes: const [],
    models: const [],
    generatedAtVersion: '0.2.0-dev',
  );
  expect(snapshot.dependencies, ['args', 'yaml']);
  expect(snapshot.assets, ['assets/icons/', 'assets/images/']);
});
```

- [ ] **Step 2: Run and observe missing-type failure**

Run: `dart test test/unit/docs/project_documentation_test.dart`

- [ ] **Step 3: Add crypto and implement immutable snapshot types**

Run: `dart pub add crypto`

Normalize set-like facts by sorting. Preserve source order only for model fields
and application routes.

- [ ] **Step 4: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/docs/project_documentation_test.dart`

```bash
git add pubspec.yaml pubspec.lock lib/src/docs/project_documentation.dart \
  test/unit/docs/project_documentation_test.dart
git commit -m "feat: define project documentation snapshot"
```

### Task 2: Scan pubspec, routes, and models without inventing facts

**Files:**
- Create: `lib/src/docs/project_documentation_scanner.dart`
- Create: `test/unit/docs/project_documentation_scanner_test.dart`

**Interfaces:**
- Consumes: `ProjectInspection`.
- Produces: `Future<ProjectDocumentation> ProjectDocumentationScanner.scan(ProjectInspection project)`.

- [ ] **Step 1: Write a representative scanner fixture**

Include pubspec dependencies/assets, one model with two final fields, and an
AutoRoute configuration containing an initial `HomeRoute` and non-initial
`ProfileRoute`.

- [ ] **Step 2: Write exact scanner assertions**

Assert project name, sorted dependencies/assets, route names/initial flags, and
model field name/type pairs. Add malformed Dart and dynamic route cases; assert
they appear in `unknownFacts` with their relative paths instead of guessed data.

- [ ] **Step 3: Run and observe failure**

Run: `dart test test/unit/docs/project_documentation_scanner_test.dart`

- [ ] **Step 4: Implement analyzer scans**

Use `ProjectInspection` for pubspec facts. Parse Dart under `lib/domain/models`
and collect class names plus final field names/types. Parse files containing
`AutoRouterConfig`; visit `InstanceCreationExpression` nodes named `AutoRoute`,
extract `page`, optional literal `path`, and literal `initial == true`.

- [ ] **Step 5: Test no-router/no-model projects**

Assert empty sections are valid and explicitly render `No routes discovered`
or `No models discovered` later.

- [ ] **Step 6: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/docs/project_documentation_scanner_test.dart`

```bash
git add lib/src/docs/project_documentation_scanner.dart \
  test/unit/docs/project_documentation_scanner_test.dart
git commit -m "feat: scan flutter project documentation facts"
```

### Task 3: Render owned Markdown and preserve user edits

**Files:**
- Create: `lib/src/docs/markdown_documentation_renderer.dart`
- Create: `lib/src/docs/documentation_manifest.dart`
- Create: `test/unit/docs/markdown_documentation_renderer_test.dart`
- Create: `test/unit/docs/documentation_manifest_test.dart`

**Interfaces:**
- Produces: `Map<String, String> MarkdownDocumentationRenderer.render(ProjectDocumentation snapshot)`.
- Produces: `DocumentationManifest(version, hashes)` with JSON encode/decode.
- Produces: `String DocumentationManifest.sha256Of(String content)`.

- [ ] **Step 1: Write Markdown snapshot tests**

Assert the renderer returns exactly these paths:

```text
docs/gold_flutter/README.md
docs/gold_flutter/architecture.md
docs/gold_flutter/dependencies.md
docs/gold_flutter/routes.md
docs/gold_flutter/assets.md
docs/gold_flutter/models.md
docs/gold_flutter/commands.md
```

Assert headings, stable list order, and explicit unknown-fact notices.

- [ ] **Step 2: Run and observe failure**

Run: `dart test test/unit/docs/markdown_documentation_renderer_test.dart`

- [ ] **Step 3: Implement deterministic Markdown**

Every file starts with:

```markdown
<!-- Generated by Gold Flutter. Edit only outside generated documentation. -->
```

The root README links the other six files. Architecture documents the detected
Gold Flutter layer paths only when they exist. Commands includes create, doctor,
arrange model, optimize, add amount-formatter, and docs examples.

- [ ] **Step 4: Write and implement manifest tests**

Manifest path is `docs/gold_flutter/.gold_flutter_docs.json` and JSON shape is:

```json
{
  "generatorVersion": "0.2.0-dev",
  "files": {
    "README.md": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

Assert a file is updateable only when absent or its current hash equals the old
manifest hash. A changed user file returns `preserve`.

- [ ] **Step 5: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/docs`

```bash
git add lib/src/docs/markdown_documentation_renderer.dart \
  lib/src/docs/documentation_manifest.dart test/unit/docs
git commit -m "feat: render owned flutter project documentation"
```

### Task 4: Generate documentation transactionally and wire CLI

**Files:**
- Create: `lib/src/docs/documentation_generator.dart`
- Create: `test/unit/docs/documentation_generator_test.dart`
- Modify: `lib/src/cli/gold_flutter_cli.dart`
- Modify: `test/unit/cli/gold_flutter_cli_test.dart`
- Create: `test/integration/docs_command_test.dart`

**Interfaces:**
- Produces: `Future<ChangePlan> DocumentationGenerator.plan(ProjectInspection project)`.
- Produces CLI: `gold_flutter docs [--dry-run] [--yes]`.

- [ ] **Step 1: Write plan tests for new, owned, and user-modified files**

Assert new files are create operations, unchanged owned files are modify
operations, and user-modified files are skipped with a reason. The manifest
always contains hashes of the content Gold Flutter last wrote, not hashes of
preserved user content.

- [ ] **Step 2: Run and observe failure**

Run: `dart test test/unit/docs/documentation_generator_test.dart`

- [ ] **Step 3: Implement generator planning**

Scan, render, read the old manifest, classify every output, and add a manifest
write. Because this command writes Markdown only, its required project
verification command is `flutter analyze`.

- [ ] **Step 4: Add failing CLI tests and wire command**

Assert help, dry run, assume yes, non-Flutter rejection, and successful output.
Use shared presenter and transaction dependencies.

- [ ] **Step 5: Add integration coverage**

Generate docs twice in a disposable fixture, manually edit `models.md`, run a
third time, and assert the user edit remains while other owned files update.

- [ ] **Step 6: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/docs test/integration/docs_command_test.dart`

```bash
git add lib/src/docs/documentation_generator.dart \
  test/unit/docs/documentation_generator_test.dart \
  lib/src/cli/gold_flutter_cli.dart test/unit/cli/gold_flutter_cli_test.dart \
  test/integration/docs_command_test.dart
git commit -m "feat: generate flutter project documentation"
```

### Task 5: Complete public documentation and CI coverage

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `CHANGELOG.md`
- Modify: `.github/workflows/ci.yml`
- Create: `docs/commands/arrange-model.md`
- Create: `docs/commands/optimize.md`
- Create: `docs/commands/amount-formatter.md`
- Create: `docs/commands/docs.md`

**Interfaces:**
- Produces complete public command reference and CI smoke workflow.

- [ ] **Step 1: Write command documentation**

Each command page includes purpose, interactive example, all flags, files
changed, dry-run example, failure/rollback behavior, limitations, and an exact
copy-paste command. Arrange-model docs state EyeAsk parsing rules explicitly.

- [ ] **Step 2: Update installation and branch testing docs**

README includes stable activation, development activation with
`--git-ref feat/developer-assistant`, and the command to return to stable main.
CONTRIBUTING describes short-lived branches, TDD, review, CI, merge, and tag.

- [ ] **Step 3: Update changelog without declaring release complete**

Add `## 0.2.0 - Unreleased` with the four commands, safe transaction engine,
EyeAsk model standard, and documentation. Keep package/CLI version
`0.2.0-dev` until the final release task.

- [ ] **Step 4: Extend CI**

After existing generator tests, create one disposable Flutter fixture and run:

```text
gold_flutter arrange model --path lib/domain/models/example_model.dart --yes
gold_flutter optimize --yes
gold_flutter add amount-formatter --yes
gold_flutter docs --yes
```

Add fixture assertions, Flutter analyze, and Flutter test. Keep the existing
Windows installer parser and add platform-neutral Dart unit tests on Windows.

- [ ] **Step 5: Validate documentation and workflow**

Run:

```bash
git diff --check
bash -n scripts/install.sh
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ci.yml')"
dart format --output=none --set-exit-if-changed bin lib test
dart analyze
dart test
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add README.md CONTRIBUTING.md CHANGELOG.md .github/workflows/ci.yml \
  docs/commands
git commit -m "docs: publish developer assistant command guide"
```

### Task 6: Prepare and verify the 0.2.0 release candidate

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/src/cli/gold_flutter_cli.dart`
- Modify: `test/unit/cli/gold_flutter_cli_test.dart`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Produces release candidate version `0.2.0`; merge/tag actions remain gated by user choice.

- [ ] **Step 1: Run full branch verification before version promotion**

Run formatting, analysis, all unit/integration tests, installer syntax, workflow
YAML parsing, secret-pattern scan, and `git diff --check`. Generate real base
and full API Flutter projects to confirm original `create` behavior remains.

- [ ] **Step 2: Install and test the public feature branch**

```bash
dart pub global activate \
  --source git \
  --git-ref feat/developer-assistant \
  https://github.com/crisantus/gold-flutter.git
```

Run version, doctor, and all four new commands against a disposable Flutter
project. Record exact outputs and failures.

- [ ] **Step 3: Promote version with a failing expectation first**

Change the version test to expect `0.2.0`, observe failure, then update
`pubspec.yaml` and `GoldFlutterCli.version`. Replace `Unreleased` with the actual
release date only on the day the release is integrated.

- [ ] **Step 4: Re-run complete verification**

Run the same full suite on the versioned tree and ensure worktree is clean after
committing.

- [ ] **Step 5: Commit release candidate**

```bash
git add pubspec.yaml lib/src/cli/gold_flutter_cli.dart \
  test/unit/cli/gold_flutter_cli_test.dart CHANGELOG.md
git commit -m "chore: prepare gold flutter 0.2.0"
```

- [ ] **Step 6: Push branch and wait for both CI jobs**

Verify exact repository root and origin, push `feat/developer-assistant`, and
wait for generator and Windows jobs. Fix any failure with a new regression test
and repeat verification.

- [ ] **Step 7: Request independent review and present integration options**

Review the complete diff from `0.1.0` to branch HEAD. Resolve Critical and
Important findings, rerun verification, then use the branch-finishing workflow
to offer local merge, PR, or keep-as-is. Do not infer the user's choice.

- [ ] **Step 8: After explicit merge approval, verify public main before tag**

Merge, run the full suite on main, push only with authorization, wait for main
CI, activate the exact public default-main install command, and run all four
commands in a disposable project. Only then create and push tag `0.2.0` with
explicit authorization.
