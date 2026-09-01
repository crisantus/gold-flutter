# Gold Flutter 0.2.0 Developer Assistant Design

## Summary

Gold Flutter 0.2.0 expands the project generator into a deterministic Flutter
project assistant. It adds four commands:

```text
gold_flutter arrange model --path <dart-file>
gold_flutter optimize
gold_flutter add amount-formatter
gold_flutter docs
```

The commands use local Dart parsing, project inspection, templates, and normal
Flutter tooling. They do not use AI. Internet access is allowed in this
release, and offline-mode behavior is intentionally deferred.

## Goals

- Arrange existing Dart models into the established EyeAsk model style.
- Provide one command for normal Flutter project-health operations.
- Install a configurable, tested amount formatter.
- Generate useful Markdown documentation from an existing Flutter project.
- Preview file changes, avoid silent overwrites, and restore modified files
  when an operation or its required verification fails.
- Keep terminal output conversational, explicit, and usable interactively or
  non-interactively.
- Document stable installation, current-main pre-release testing, and every new
  command for open-source users.

## Non-goals

Version 0.2.0 will not:

- use an AI model or require an AI API key;
- provide an offline mode or manage dependency caches;
- generate authentication, notifications, profiles, pagination, uploads,
  connectivity, localization, application updates, realtime, or secure-storage
  modules;
- rewrite application business logic;
- promise automatic runtime-performance optimization;
- host a documentation website or module registry;
- overwrite an unsupported or conflicting source file.

## User experience

Every file-changing command follows this flow:

```text
inspect project
  -> validate input
  -> calculate change plan
  -> print created/modified/skipped files
  -> request confirmation
  -> snapshot affected files
  -> apply changes
  -> format and run command-specific verification
  -> keep the result or restore the snapshot
```

Common flags are:

- `--dry-run`: print the complete change plan without writing files;
- `--yes`: accept safe planned changes without an interactive confirmation.

The command warns when the project has uncommitted Git changes. A dirty tree
does not automatically block the command because the transaction owns only the
files named in its change plan. Files outside that plan are never restored or
modified.

## Shared architecture

### ProjectInspector

`ProjectInspector` resolves the project root and confirms that `pubspec.yaml`
declares a Flutter project. It reads project metadata, source and test paths,
dependencies, asset declarations, generated-code markers, and available Git
status. Commands consume a typed project description rather than re-scanning
the filesystem independently.

### ChangePlan

A `ChangePlan` contains ordered create, modify, command, and verification
operations. Each file operation includes a reason suitable for terminal
display. Plans reject duplicate targets, writes outside the project root,
unplanned overwrites, and path traversal.

### ChangeTransaction

`ChangeTransaction` records whether each affected path existed and stores its
original bytes in a generator-owned temporary directory. It writes only the
approved plan. If writing, formatting, or required verification fails, it
restores existing files and removes files created by the transaction. It never
uses a broad Git reset or checkout.

### Command output

Commands print concise stages and a final report. Failures include the failing
operation, captured tool output, whether restoration succeeded, and a suggested
next action. Success includes created, modified, preserved, and skipped files.

## `arrange model`

### Invocation

```bash
gold_flutter arrange model \
  --path lib/domain/models/user_model.dart
```

Optional flags:

- `--copy-with`: add `copyWith` to eligible classes that do not already have
  it;
- `--test`: add or update a focused model test;
- `--dry-run` and `--yes`: use the shared change behavior.

Existing `copyWith` methods are preserved. A new `copyWith` is not added unless
`--copy-with` is supplied.

### Source of truth

The arranger follows EyeAsk model conventions. Representative input and
expected-output fixtures will be committed under `test/fixtures/models/` so
the behavior remains stable and reviewable without access to the original
application.

The canonical class member order is:

1. final fields;
2. required constructor;
3. `fromJson` factory;
4. `empty` factory;
5. list or envelope parsing helpers when present or requested by the source;
6. `toJson`;
7. an existing or explicitly requested `copyWith`;
8. preserved custom getters, converters, and business methods.

Top-level JSON string encode/decode helpers are preserved when present. When
absent, they are generated for the first public model class in the file, which
EyeAsk treats as the root response model.

### Parsing rules

The Dart analyzer parses compilation units, declarations, fields, constructors,
factory methods, annotations, documentation comments, source ranges, and JSON
key expressions. The implementation does not use regular expressions to parse
Dart syntax.

Supported field shapes are:

- `String`, `int`, `double`, `num`, and `bool`;
- nullable versions of supported fields;
- `DateTime` and `DateTime?`;
- nested model objects;
- `List<T>` where `T` is a supported primitive or a model in scope;
- enums that already have a converter Gold Flutter can preserve;
- response shapes that are direct objects or lists, `data`, or `data.items`.

JSON keys may be snake case or camel case. Existing keys are preserved. When a
field has no discoverable key, the arranger derives a snake-case key and shows
it in the preview. Existing direct, `data`, and `data.items` envelope parsing is
preserved. If the source contains no discoverable envelope behavior, the
arranger generates direct-object parsing and does not invent a wrapper.

### EyeAsk safety conversions

Raw primitive API values pass through `toString()` before typed parsing.
Generated patterns follow these semantics:

```dart
value: (json?["value"] ?? "").toString(),
count: int.tryParse((json?["count"] ?? "").toString()) ?? 0,
price: double.tryParse((json?["price"] ?? "").toString()) ?? 0.0,
total: num.tryParse((json?["total"] ?? "").toString()) ?? 0,
enabled: json?["enabled"] is bool
    ? json!["enabled"] as bool
    : (json?["enabled"] ?? "").toString() == "true",
createdAt: DateTime.tryParse(
      (json?["created_at"] ?? "").toString(),
    ) ??
    DateTime.now(),
deletedAt: DateTime.tryParse(
  (json?["deleted_at"] ?? "").toString(),
),
```

The declared Dart type is preserved. A date represented as `String` remains a
string; a date represented as `DateTime` is safely parsed. Non-null dates fall
back to `DateTime.now()`, while nullable dates fall back to `null`.

Nested models fall back to their `empty()` factories. Lists accept only list
payloads and otherwise fall back to an empty list. `toJson` serializes dates as
ISO-8601 strings and recursively serializes nested objects and lists.

### Preservation and refusal

The arranger preserves imports, annotations, documentation, custom getters,
custom methods, and enum/date converters that do not conflict with generated
structural members. It may replace constructors, `empty`, `fromJson`,
`toJson`, recognized list helpers, and `copyWith` only when the change plan
names them explicitly.

The command preserves safe local aliases through direct, `data`, and
`data.items` payloads. It refuses the entire file without writing when it
encounters an unsupported or imported/external model boundary, ambiguous JSON
mapping, nested function/closure alias scope, syntactically invalid source,
conflicting class declarations, or a custom structural method it cannot
preserve safely. The terminal identifies the unsupported declaration.

### Verification

After writing, the command runs Dart formatting and analysis for the project.
When `--test` is supplied, it creates a focused test when the target does not
exist. An existing test is updated only when its ownership marker identifies it
as Gold Flutter generated; otherwise it is preserved and reported. The focused
test calls the first public root class's direct-object `fromJson` and `toJson`.
Preserved top-level list/envelope helpers remain compatible, but a preserved
root factory that itself reads an envelope refuses `--test`. The focused test
runs after generation. A failure restores the original model and test files.

## `optimize`

### Invocation

```bash
gold_flutter optimize
```

Version 0.2.0 defines optimization as project-health verification, not automatic
runtime tuning. The command runs these stages in order:

1. `flutter pub get`;
2. build runner when the project declares build runner and contains supported
   generated-code markers;
3. Dart formatting for `lib` and `test` when those directories exist;
4. `flutter analyze`;
5. `flutter test` when the project has a test directory;
6. a read-only check for missing declared asset paths and stale generated
   source markers;
7. a terminal summary.

`gold_flutter optimize --dry-run` prints detected stages and checks without
running mutating commands. `--yes` skips confirmation but does not suppress
tool output or failures.

The optimizer may change formatter output and generated source. It does not
remove dependencies, alter architecture, or edit application logic in 0.2.0.
If a stage fails, later stages do not run. Files modified directly by the
transaction are restored. Before format or build runner executes, the
transaction snapshots `lib`, `test`, `pubspec.yaml`, and `pubspec.lock` when
they exist, so source changes made by those tools can also be restored.
External tool caches and downloaded packages are not rolled back.

## `add amount-formatter`

### Invocation

```bash
gold_flutter add amount-formatter
```

The interactive command asks for currency symbol, locale, decimal digits,
whether grouped thousands should be displayed, and hidden-balance text. Flags
provide the same answers for non-interactive use.

The plan:

- adds `intl` through normal Flutter dependency resolution when it is missing;
- creates `lib/core/utils/money_formatter.dart`;
- creates `test/core/utils/money_formatter_test.dart`;
- refuses to overwrite either file unless it already matches a recognized
  Gold Flutter generated file that can be updated safely;
- formats, analyzes, and runs the focused test.

The transaction snapshots `pubspec.yaml` and `pubspec.lock` before dependency
resolution so a failed installation restores both project files. Downloaded
package-cache entries remain available.

The formatter supports a decimal and whole-number representation and a hidden
balance. With the default Nigerian configuration, representative output is:

```text
12      -> ₦12.00
12.5    -> ₦12.50
1200    -> ₦1,200.00
hidden  -> ₦ •••••
```

## `docs`

### Invocation

```bash
gold_flutter docs
```

The documentation generator scans the local project and writes Markdown under
`docs/gold_flutter/`:

```text
README.md
architecture.md
dependencies.md
routes.md
assets.md
models.md
commands.md
```

It documents only information discoverable from project files. It identifies
unknown or dynamic behavior explicitly instead of inventing descriptions. A
generated manifest records file ownership and content hashes so later runs can
update owned sections without overwriting user-authored documentation.

The repository's own README and command documentation will also explain:

- stable public installation;
- explicit `main` installation with `--git-ref main`;
- local-main pre-release testing and optional contributor branches;
- all new commands and flags;
- previews, confirmation, rollback, limitations, and failure recovery;
- contribution and release workflow.

## Testing strategy

Unit coverage includes:

- project discovery and path containment;
- change-plan conflicts, dry runs, snapshots, rollback, and dirty-tree warnings;
- EyeAsk golden model fixtures;
- primitive, nullable, date, nested-model, list, enum-converter, JSON-key, and
  response-envelope behavior;
- custom member preservation and unsupported-model refusal;
- optimizer stage selection, ordering, captured output, and early failure;
- amount formatter rendering and output;
- documentation scanning, ownership manifests, and stable snapshots;
- interactive answers and non-interactive flags.

Integration coverage creates disposable Flutter projects and exercises every
new command. CI runs generator unit tests plus representative command smoke
tests on Linux. Windows CI parses installer scripts and runs platform-neutral
CLI tests. Generated files must format and analyze successfully, and generated
tests must pass.

## Release workflow

Development and debugging occur on local `main` with version `0.2.0-dev`.
Documentation includes this explicit main-install command:

```bash
dart pub global activate \
  --source git \
  --git-ref main \
  https://github.com/crisantus/gold-flutter.git
```

No push, tag, or release occurs without explicit approval. After local
verification and independent review, `main` is pushed, GitHub Actions must pass,
and the exact public installation command is tested. Release tag `0.2.0` is
created only after separate approval. External contributors may still use
short-lived branches and pull requests.
