# EyeAsk Model Arranger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `gold_flutter arrange model --path <file>` so existing Dart models are safely rewritten into the approved EyeAsk structure.

**Architecture:** Dart analyzer AST traversal extracts model classes, field types, JSON keys, and preservable members into immutable specifications. A deterministic renderer emits EyeAsk-style code, while the shared change engine previews, applies, verifies, and rolls back the change. Golden fixtures make EyeAsk output the executable source of truth.

**Tech Stack:** Dart 3.5+, package:analyzer, package:path, package:test, shared Developer Assistant Core

**Spec:** `docs/superpowers/specs/2026-08-31-developer-assistant-design.md`

## Global Constraints

- Complete `2026-08-31-developer-assistant-core.md` first.
- Parse Dart with analyzer AST; do not parse Dart declarations with regex.
- Preserve the declared Dart type and pass raw primitive JSON values through `toString()` before safe typed parsing.
- Follow committed EyeAsk golden fixtures exactly.
- Preserve custom imports, annotations, documentation, getters, methods, and supported converters.
- Refuse the complete file before writing when any class is ambiguous or unsupported.
- New `copyWith` generation requires `--copy-with`.
- Existing non-Gold tests are never overwritten.

## File map

- Create `lib/src/model/model_field_spec.dart`: supported field and JSON metadata.
- Create `lib/src/model/model_class_spec.dart`: class-level structural and preserved members.
- Create `lib/src/model/model_file_spec.dart`: imports, root helpers, and ordered classes.
- Create `lib/src/model/dart_model_parser.dart`: analyzer AST extraction and refusal diagnostics.
- Create `lib/src/model/eyeask_model_renderer.dart`: deterministic EyeAsk Dart source.
- Create `lib/src/model/model_arranger.dart`: project validation, plan, and verification orchestration.
- Create `lib/src/model/model_test_renderer.dart`: optional defensive parser test.
- Create golden fixtures under `test/fixtures/models/`.
- Create matching unit tests under `test/unit/model/`.
- Modify `pubspec.yaml`, `pubspec.lock`, `lib/src/cli/gold_flutter_cli.dart`, and CLI tests.

---

### Task 1: Add analyzer and model specification types

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/src/model/model_field_spec.dart`
- Create: `lib/src/model/model_class_spec.dart`
- Create: `lib/src/model/model_file_spec.dart`
- Create: `test/unit/model/model_spec_test.dart`

**Interfaces:**
- Produces: `enum ModelFieldKind { string, integer, doubleValue, numeric, boolean, dateTime, nestedModel, list, enumeration }`
- Produces: `ModelFieldSpec(name, typeSource, jsonKey, kind, isNullable, nestedType, sourceOffset)`
- Produces: `ModelClassSpec(name, fields, annotations, documentation, preservedMembers, hasCopyWith, sourceOffset)`
- Produces: `ModelFileSpec(imports, rootClassName, classes, preservedTopLevelDeclarations)`

- [ ] **Step 1: Add a failing immutability and ordering test**

```dart
test('model specs preserve source ordering and cannot be mutated', () {
  final spec = ModelClassSpec(
    name: 'UserModel',
    fields: const [
      ModelFieldSpec(
        name: 'id',
        typeSource: 'String',
        jsonKey: 'id',
        kind: ModelFieldKind.string,
        isNullable: false,
        nestedType: null,
        sourceOffset: 10,
      ),
    ],
    annotations: const [],
    documentation: null,
    preservedMembers: const [],
    hasCopyWith: false,
    sourceOffset: 0,
  );
  expect(spec.fields.single.name, 'id');
  expect(() => spec.fields.add(spec.fields.single), throwsUnsupportedError);
});
```

- [ ] **Step 2: Run the test and observe missing-type failures**

Run: `dart test test/unit/model/model_spec_test.dart`

- [ ] **Step 3: Add analyzer through Dart Pub**

Run: `dart pub add analyzer`

Expected: `pubspec.yaml` and `pubspec.lock` resolve an analyzer version
compatible with the package's Dart SDK range.

- [ ] **Step 4: Implement immutable specification types**

Copy input lists with `List.unmodifiable`, validate nonempty names/type sources,
and require `nestedType` for nested/list/enum shapes that need it.

- [ ] **Step 5: Run, analyze, and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/model/model_spec_test.dart`

```bash
git add pubspec.yaml pubspec.lock lib/src/model/model_* \
  test/unit/model/model_spec_test.dart
git commit -m "feat: define parsed model specifications"
```

### Task 2: Parse supported Dart models with analyzer AST

**Files:**
- Create: `lib/src/model/dart_model_parser.dart`
- Create: `test/unit/model/dart_model_parser_test.dart`
- Create: `test/fixtures/models/eyeask_input.dart`
- Create: `test/fixtures/models/unsupported_input.dart`

**Interfaces:**
- Consumes: Dart source string and source path.
- Produces: `ModelParseResult(spec, diagnostics)` from `DartModelParser.parse(source, path)`.
- Throws no parser exception for user source; fatal syntax/shape problems return diagnostics with `isSafe == false`.

- [ ] **Step 1: Add a representative EyeAsk input fixture**

```dart
import 'dart:convert';

class ReportModel {
  final String id;
  final int page;
  final bool ready;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final UserModel user;
  final List<ItemModel> items;

  ReportModel({
    required this.id,
    required this.page,
    required this.ready,
    required this.createdAt,
    required this.deletedAt,
    required this.user,
    required this.items,
  });

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
        page: int.tryParse((json?["current_page"] ?? "").toString()) ?? 1,
        ready: json?["ready"] is bool
            ? json!["ready"] as bool
            : (json?["ready"] ?? "").toString() == "true",
        createdAt: DateTime.tryParse(
              (json?["created_at"] ?? "").toString(),
            ) ??
            DateTime.now(),
        deletedAt: DateTime.tryParse(
          (json?["deleted_at"] ?? "").toString(),
        ),
        user: UserModel.fromJson(json?["user"]),
        items: (json?["items"] is List ? json!["items"] as List : [])
            .map((item) => ItemModel.fromJson(item))
            .toList(),
      );

  String get label => '$id:$page';
}
```

- [ ] **Step 2: Write extraction and refusal tests**

Assert exact class/field order, `current_page` discovery for `page`, nullable
date classification, nested/list type discovery, and preservation of `label`.
The unsupported fixture contains `Map<String, List<Object?>> grouped`; assert a
diagnostic naming `ReportModel.grouped` and `isSafe == false`.

- [ ] **Step 3: Run the parser test and verify failure**

Run: `dart test test/unit/model/dart_model_parser_test.dart`

- [ ] **Step 4: Implement analyzer parsing**

Use `parseString(content: source, path: path, throwIfDiagnostics: false)`. Reject
error-severity parse diagnostics. Walk `CompilationUnit.declarations`, accepting
class declarations and preserving other top-level declarations with
`node.toSource()`.

For each class:

- collect non-static `final` fields from `FieldDeclaration`;
- map `NamedType` source to the supported kind table;
- find the matching named argument inside the redirecting or factory
  `fromJson` return expression;
- visit `IndexExpression` nodes inside that argument and take the innermost
  string literal key associated with `json`;
- classify constructors, `empty`, `fromJson`, `toJson`, recognized list
  helpers, and `copyWith` as structural;
- preserve all other members by exact source substring and source offset.

- [ ] **Step 5: Add syntax, duplicate class, enum converter, and multiple-class tests**

Use an enum fixture with an existing `_statusFromJson(dynamic value)` method;
assert the field is accepted and the converter source is preserved. Assert the
entire result is unsafe for invalid syntax or duplicate class names.

- [ ] **Step 6: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/model/dart_model_parser_test.dart`

```bash
git add lib/src/model/dart_model_parser.dart test/unit/model \
  test/fixtures/models/eyeask_input.dart test/fixtures/models/unsupported_input.dart
git commit -m "feat: parse existing dart model structure"
```

### Task 3: Render exact EyeAsk model output

**Files:**
- Create: `lib/src/model/eyeask_model_renderer.dart`
- Create: `test/unit/model/eyeask_model_renderer_test.dart`
- Create: `test/fixtures/models/eyeask_expected.dart`

**Interfaces:**
- Consumes: `ModelFileSpec`, `bool addCopyWith`.
- Produces: `String EyeAskModelRenderer.render(ModelFileSpec spec, {required bool addCopyWith})`.

- [ ] **Step 1: Commit the expected golden fixture before implementation**

The fixture must contain this parsing matrix:

```dart
id: (json?["id"] ?? "").toString(),
page: int.tryParse((json?["current_page"] ?? "").toString()) ?? 0,
price: double.tryParse((json?["price"] ?? "").toString()) ?? 0.0,
total: num.tryParse((json?["total"] ?? "").toString()) ?? 0,
ready: json?["ready"] is bool
    ? json!["ready"] as bool
    : (json?["ready"] ?? "").toString() == "true",
createdAt: DateTime.tryParse(
      (json?["created_at"] ?? "").toString(),
    ) ??
    DateTime.now(),
deletedAt: DateTime.tryParse(
  (json?["deleted_at"] ?? "").toString(),
),
```

It also contains nested `.empty()` fallback, safe list fallback, ISO-8601 date
serialization, root JSON encode/decode helpers, and the preserved custom getter.

- [ ] **Step 2: Write a golden equality test**

```dart
test('renders the approved EyeAsk model style exactly', () {
  final parsed = parser.parse(inputSource, 'eyeask_input.dart');
  final rendered = const EyeAskModelRenderer().render(
    parsed.spec!,
    addCopyWith: false,
  );
  expect(rendered, expectedSource);
});
```

- [ ] **Step 3: Run the golden test and observe failure**

Run: `dart test test/unit/model/eyeask_model_renderer_test.dart`

- [ ] **Step 4: Implement deterministic rendering**

Emit double-quoted JSON keys and empty strings to match EyeAsk. Primitive empty
defaults are `""`, `0`, `0.0`, `0`, and `false`. Non-null dates use
`DateTime.now()`; nullable fields use `null`; nested models use `Type.empty()`;
lists use `[]`. Use discovered JSON keys without renaming them.

Render root helpers as:

```dart
RootModel rootModelFromJson(String str) =>
    RootModel.fromJson(json.decode(str) as Map<String, dynamic>);

String rootModelToJson(RootModel data) => json.encode(data.toJson());
```

- [ ] **Step 5: Test `--copy-with` behavior**

Assert an existing `copyWith` is preserved byte-for-byte. Assert a missing
`copyWith` is absent when `addCopyWith` is false and generated when true. For a
nullable field, generated `copyWith` preserves the current value when the
argument is null; clearing nullable values is outside 0.2.0 scope and must be
documented in command output.

- [ ] **Step 6: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/model/eyeask_model_renderer_test.dart`

```bash
git add lib/src/model/eyeask_model_renderer.dart \
  test/unit/model/eyeask_model_renderer_test.dart \
  test/fixtures/models/eyeask_expected.dart
git commit -m "feat: render eyeask style dart models"
```

### Task 4: Build transactional arrangement and optional tests

**Files:**
- Create: `lib/src/model/model_arranger.dart`
- Create: `lib/src/model/model_test_renderer.dart`
- Create: `test/unit/model/model_arranger_test.dart`
- Create: `test/unit/model/model_test_renderer_test.dart`

**Interfaces:**
- Consumes: `ProjectInspection`, parser, renderer, shared change engine.
- Produces: `Future<ChangePlan> ModelArranger.plan({required ProjectInspection project, required String path, required bool addCopyWith, required bool addTest})`.

- [ ] **Step 1: Write unsafe-file and dry plan tests**

Assert a path outside project root is rejected, unsupported parser diagnostics
produce `ModelArrangementException` without a plan, and a supported file plan
contains exactly one modify operation plus format/analyze commands.

- [ ] **Step 2: Run and observe failure**

Run: `dart test test/unit/model/model_arranger_test.dart`

- [ ] **Step 3: Implement the arranger plan**

Resolve the path against `project.root`, verify it is a `.dart` file under
`lib/domain/models/`, parse and render it, then return a `ChangePlan` with:

```dart
PlannedFileChange(
  relativePath: relativePath,
  content: rendered,
  kind: FileChangeKind.modify,
  reason: 'Arrange models using the EyeAsk standard',
)
```

Add `dart format $relativePath` and `flutter analyze` planned commands.

- [ ] **Step 4: Implement the focused test renderer**

Generate tests for `empty`, null/missing primitive JSON, nested/list fallback,
and JSON round trip. Derive the test path by replacing `lib/` with `test/` and
suffixing `_test.dart`. Add a Gold Flutter ownership comment on line one. If an
existing test lacks that marker, report it as preserved and omit the test write.

- [ ] **Step 5: Test rollback through the real change transaction**

Use a fake analyzer failure and assert the original model/test contents return.

- [ ] **Step 6: Run and commit**

Run: `dart format lib test && dart analyze && dart test test/unit/model`

```bash
git add lib/src/model/model_arranger.dart lib/src/model/model_test_renderer.dart \
  test/unit/model/model_arranger_test.dart \
  test/unit/model/model_test_renderer_test.dart
git commit -m "feat: arrange models transactionally"
```

### Task 5: Wire the nested CLI command and run a real fixture

**Files:**
- Modify: `lib/src/cli/gold_flutter_cli.dart`
- Modify: `test/unit/cli/gold_flutter_cli_test.dart`
- Create: `test/integration/arrange_model_command_test.dart`
- Modify: `README.md`

**Interfaces:**
- Produces CLI: `gold_flutter arrange model --path <file> [--copy-with] [--test] [--dry-run] [--yes]`.

- [ ] **Step 1: Add failing parser/help tests**

Assert `arrange model --help` lists all five options, missing `--path` exits 64,
and `--dry-run` invokes no transaction.

- [ ] **Step 2: Run and observe command-not-found failures**

Run: `dart test test/unit/cli/gold_flutter_cli_test.dart --name arrange`

- [ ] **Step 3: Add nested args parsers and dependency injection**

Add an `arrange` command containing a `model` subcommand. Inject a
`ModelArranger` and `ChangeTransaction` into `GoldFlutterCli`, preserving
defaults for current callers. Catch `ModelArrangementException` and return 64
for invalid input or 1 for failed verification.

- [ ] **Step 4: Add the integration test**

Copy `eyeask_input.dart` into a disposable Flutter fixture, invoke the CLI with
`--yes --test`, and assert the model equals the golden output and the owned test
exists. Use fake format/analyze outputs so the test is deterministic.

- [ ] **Step 5: Document command and limitations**

README examples must include branch installation, preview, apply, `--copy-with`,
`--test`, supported field shapes, EyeAsk conversion rules, and refusal behavior.

- [ ] **Step 6: Verify and commit**

Run: `dart format --output=none --set-exit-if-changed bin lib test && dart analyze && dart test`

```bash
git add lib/src/cli/gold_flutter_cli.dart test/unit/cli/gold_flutter_cli_test.dart \
  test/integration/arrange_model_command_test.dart README.md
git commit -m "feat: add eyeask model arrangement command"
```
