# Gold Flutter

`gold_flutter` is an opinionated, interactive Flutter project generator built
around Riverpod 3, AutoRoute, layered data boundaries, consistent themes,
responsive UI, assets, useful examples, and focused tests.

It creates the foundation I want at the beginning of a real Flutter project,
while keeping API, authentication, refresh-token, and sample-feature code
optional.

## What it generates

Every generated application includes:

- the standard Flutter platform projects
- Riverpod 3 with a root `ProviderScope`
- AutoRoute with generated, typed routes
- `MaterialApp.router`, light and dark themes, and a responsive starter screen
- `business`, `core`, `data`, `domain`, and `presentation` layers
- `assets/fonts`, `assets/icons`, `assets/images`, and `assets/svgs`
- focused starter tests and project-local agent instructions
- explicit local layout spacing—no global spacing class

When API support is selected it can also generate Dio services, connectivity,
typed exceptions and failures, abstract/concrete remote sources, repositories,
Riverpod ViewModels, secure authentication, coordinated refresh tokens, and a
complete sample API feature.

## Prerequisites

Install the following first:

1. [Flutter](https://docs.flutter.dev/get-started/install)
2. Git
3. Dart, which is included with Flutter

Confirm Flutter is available:

```bash
flutter doctor
dart --version
git --version
```

## Install

Because this repository is public, installation does not require a GitHub
account, SSH key, or access token:

```bash
dart pub global activate --source git --git-ref main \
  https://github.com/crisantus/gold-flutter.git
```

The explicit `--git-ref main` installs the current public `main` branch and is
also the recommended way to test unreleased command changes from `main`.

On macOS or Linux, the repository also provides a convenience installer:

```bash
curl -fsSLO https://raw.githubusercontent.com/crisantus/gold-flutter/main/scripts/install.sh
bash install.sh
```

Review downloaded scripts before running them. The direct Dart activation
command above remains the simplest transparent installation method.

On Windows PowerShell, the equivalent convenience installer is:

```powershell
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/crisantus/gold-flutter/main/scripts/install.ps1 `
  -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

If your terminal cannot find `gold_flutter`, add Dart's global executable
directory to your `PATH`.

macOS and Linux:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Add that line to `~/.zshrc`, `~/.bashrc`, or the startup file used by your
shell so it remains available after restarting the terminal.

Windows uses:

```text
%LOCALAPPDATA%\Pub\Cache\bin
```

## Create a project

Move into the directory that should contain the new project, then run:

```bash
gold_flutter doctor
gold_flutter create
```

The wizard asks for:

1. Project display name
2. Dart `snake_case` project name
3. Package/application ID, such as `com.company.app`
4. Target platforms
5. Whether the application consumes APIs
6. API base URL when API support is enabled
7. Whether users sign in to protected API endpoints
8. Whether the backend issues refresh tokens
9. Whether to include a complete sample API feature
10. Final confirmation

Press Enter to accept a displayed default. Authentication means the backend
issues a token after sign-in for protected requests; it is not required for a
public API.

The generator creates a new child directory. It refuses to overwrite a
non-empty directory and does not provide a force option.

## Non-interactive example

For scripts or CI:

```bash
gold_flutter create \
  --display-name "My App" \
  --project-name my_app \
  --application-id com.company.myapp \
  --platforms android,ios,web \
  --api \
  --api-base-url https://api.example.com \
  --auth \
  --refresh-tokens \
  --sample-api \
  --yes
```

Use `--no-api`, `--no-auth`, `--no-refresh-tokens`, or `--no-sample-api` to
disable a choice explicitly.

## Arrange an existing model

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
of it is understood. Supported fields are:

- `String`, `int`, `double`, `num`, and `bool`, including nullable forms;
- `DateTime` and `DateTime?`;
- nested model objects;
- `List<T>` where `T` is a supported primitive, `DateTime`, or a model class
  declared in the same file;
- enum fields that call a preservable converter named for the field, such as
  `_statusFromJson`.

Imported/external model lists and enum lists are not arranged in this release;
they are refused because the file does not contain enough structural proof to
regenerate them safely. Map-shaped fields, unsupported generics, non-final
fields, invalid Dart, ambiguous constructors, and conflicting structural
members also cause a full-file refusal with no write.

Each field must map to exactly one discoverable JSON key in its `fromJson`
argument. Snake-case, camelCase, and escaped string-literal keys are preserved.
Missing or ambiguous mappings are refused rather than guessed. A model
`fromJson` reads the direct map it receives. Safe top-level object/list helpers
that unwrap direct responses, `data`, or `data.items` remain preserved; the
arranger does not invent a response envelope.

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

## Update

After improvements are pushed to this repository, install the newest version
with the same command:

```bash
dart pub global activate --source git --git-ref main \
  https://github.com/crisantus/gold-flutter.git
```

Generator updates affect newly created projects only. Existing Flutter apps
are changed only when you explicitly run a file-changing assistant command,
review its plan, and confirm it.

## Uninstall

```bash
dart pub global deactivate gold_flutter
```

## Develop the generator

```bash
git clone https://github.com/crisantus/gold-flutter.git
cd gold-flutter
dart pub get
dart analyze
dart test
```

To smoke-test the public `main` build instead of a local checkout, activate the
branch explicitly and inspect the nested command:

```bash
dart pub global activate --source git --git-ref main \
  https://github.com/crisantus/gold-flutter.git
gold_flutter arrange model --help
```

Make changes on a feature branch, keep tests green, and open a pull request.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the release workflow.

## Security

Templates contain placeholders and example URLs only. Never commit API keys,
tokens, signing certificates, service-account files, production `.env` files,
or real credentials to this public repository or to a generated application.

## License

Gold Flutter is available under the [MIT License](LICENSE.md).
