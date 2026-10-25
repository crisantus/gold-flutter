# Arrange model


Run the model arranger from anywhere inside the target Flutter project. The
model path must resolve to an existing Dart file under
`lib/domain/models/` in that project.

Preview the complete file and command plan without changing files or consuming
confirmation input:

```bash
gold_flutter arrange model \
  --path lib/domain/models/report_model.dart \
  --dry-run
```

Omit `--dry-run` to preview the same plan and confirm it interactively, or use
`--yes` for a reviewed script or CI job:

```bash
gold_flutter arrange model \
  --path lib/domain/models/report_model.dart \
  --yes
```

Add `copyWith` to eligible classes and create or update the focused,
Gold-owned model test with:

```bash
gold_flutter arrange model \
  --path lib/domain/models/report_model.dart \
  --copy-with \
  --test \
  --yes
```

The command options are:

- `--path <file>`: required project-relative or contained absolute path to the
  model file.
- `--copy-with`: generate `copyWith` for eligible classes that do not already
  define a supported instance `copyWith`; existing supported methods are
  preserved.
- `--test`: generate or update the mirrored focused test under `test/` and run
  that test after analysis.
- `--dry-run`: print the plan and exit without starting the transaction,
  writing files, running formatter/analysis/tests, or reading confirmation.
- `--yes`, `-y`: apply the displayed plan without reading confirmation.
- `--help`, `-h`: display the model-arranger options.

### Supported model shapes

The arranger uses the Dart analyzer and rewrites a complete file only when all
of it is understood. The first public class is the root model; private classes
that appear before it keep their source order. Supported fields are:

- `String`, `int`, `double`, `num`, and `bool`, including nullable forms;
- `DateTime` and `DateTime?`;
- nested model objects;
- `List<T>` where `T` is a supported primitive, `DateTime`, or a model class
  declared in the same file;
- enum fields that call a preservable converter named for the field, such as
  `_statusFromJson`.

Nested model fields and model-list elements must be declared in the same Dart
file. Imported/external model fields, imported/external model lists, and enum
lists are not arranged in this release because the file does not contain enough
structural proof to regenerate them safely. Map-shaped fields, unsupported
generics, non-final fields, invalid Dart, ambiguous constructors, and
conflicting structural members also cause a full-file refusal with no write.

Snake-case, camelCase, and escaped string-literal JSON keys discovered in
`fromJson` are preserved. When a field has no discoverable key, the arranger
derives an acronym-aware snake-case key, such as `currentPage` to
`current_page`, and shows that decision in the preview. Multiple conflicting
keys for one field remain ambiguous and cause a full-file refusal.

Existing direct-list, `data`, and `data.items` response handling is preserved,
including safe local-variable and top-level-helper aliases. The arranger never
invents an envelope. It refuses aliases that are reassigned, cyclic, ambiguous,
or hidden inside a nested function or closure because those scopes cannot be
rewritten safely.

The canonical output orders final fields, the required constructor,
`fromJson`, `empty`, `toJson`, an existing or requested `copyWith`, and then
preserved custom members. Imports, annotations, documentation, safe top-level
declarations, custom getters, custom methods, and supported enum converters
are preserved.

### EyeAsk conversions

Primitive input is normalized through `toString()` before typed parsing. The
generated scalar behavior is exactly:

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

Nullable `int`, `double`, `num`, and `DateTime` values omit the non-null
fallback, so failed parsing returns `null`. String and boolean parsing still
produce `""` and `false` for missing or null input. Booleans preserve an actual
JSON boolean; other values are true only when `toString()` equals lowercase
`"true"` exactly. A field declared as `String`, including a date-looking
string, stays a string.

List payloads must be actual lists or they become `[]`. Each primitive/date
item uses the same string conversion and fallback rules; local model items use
their `fromJson`. `toJson` writes dates as ISO-8601 strings and recursively
writes nested models and local-model lists.

### Safety boundaries and rollback

`--test` refuses a root class, root field, or enum type that is library-private
because a separate test library cannot safely reference it. Arranging that
otherwise-supported source without `--test` remains possible. Generated tests
start with Gold Flutter's ownership marker. An existing test is updated only
when that marker is its first line; an unowned test is preserved and reported.

Generated tests call the root class's `fromJson` and `toJson` directly. A
preserved top-level direct-list, `data`, or `data.items` helper is therefore
compatible with `--test` when the root class itself accepts a direct object. If
the root class's preserved `fromJson` factory reads an envelope, arrangement is
still supported without `--test`, but focused test generation is refused in
this release.

Generated `copyWith` uses `argument ?? this.field`. This keeps ordinary calls
simple but means it cannot deliberately clear a nullable field to `null` in
this release. Existing supported `copyWith` implementations are preserved.

Before applying, the transaction rechecks the exact model and owned-test text
shown in the preview. It snapshots only the planned model and owned test, then
runs targeted Dart formatting, `flutter analyze`, and the generated focused
test when requested. A write, formatting, analysis, or focused-test failure
returns exit code 1 and restores the original bytes, removing a newly created
owned test. Invalid or unsafe arrangement input returns exit code 64 without a
transaction. Gold Flutter never uses a broad Git reset and does not restore
unrelated files or external tool caches.
