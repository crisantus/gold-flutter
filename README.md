# Gold Flutter

Gold Flutter creates a Flutter app with Riverpod 3, AutoRoute, light and dark
themes, and a ready-to-use folder structure. Choose whether to include API
support, token authentication, refresh tokens, and a sample API feature.

## Install

You need [Flutter](https://docs.flutter.dev/get-started/install), its bundled
Dart SDK (`>=3.5.0 <4.0.0`), and Git installed and available in your terminal.

```bash
dart pub global activate --source git --git-ref main \
  https://github.com/crisantus/gold-flutter.git
```

Check that everything is ready:

```bash
gold_flutter doctor
```

If your terminal says `gold_flutter` is not found, see [PATH setup](#path-setup).

## Create and run your first app

Run this in the folder where you want to create your project:

```bash
gold_flutter create
```

The wizard asks for your app name, Dart project name (for example, `my_app`),
application ID (for example, `com.company.myapp`), and target platforms. It then
asks whether you need APIs, authentication, refresh tokens, and a sample API
feature. API questions appear only when the relevant feature is enabled.

Press Enter to accept a default. In the platform checklist, use the arrow keys
to move, Space to toggle a platform, and Enter to confirm. All platforms are
selected by default; select at least one. If the checklist is unavailable, use
the numbered fallback or enter platform names such as `android ios web`.

Gold Flutter creates a child folder using your Dart project name, installs
dependencies, generates routes, formats the code, and runs analysis and tests.
It refuses to overwrite a non-empty folder.

When creation finishes, enter that folder and run your app:

```bash
cd my_app
flutter run
```

Replace `my_app` with the project name you chose. Flutter lists available
devices when a target needs to be selected.

## What you get

Every app includes:

- Riverpod 3 for state management and dependency injection.
- AutoRoute for typed navigation and `MaterialApp.router`.
- Light and dark themes, a responsive starter screen, and starter tests.
- Folders for fonts, icons, images, and SVGs.
- Project instructions in `AGENTS.md`, a local Flutter development skill, and
  style and performance guides.

The generated code follows this structure:

| Folder | Purpose |
| --- | --- |
| `lib/presentation/` | Screens and widgets |
| `lib/business/` | Riverpod ViewModels and feature actions |
| `lib/domain/` | Models and request payloads |
| `lib/data/` | Repositories and remote/local sources |
| `lib/core/` | Routing, themes, networking, and shared utilities |
| `assets/` | Fonts, icons, images, and SVGs |

### Optional features

| Choice | What it adds |
| --- | --- |
| API support | Dio, connectivity checks, typed errors, and network services |
| Authentication | Bearer-token requests, token storage using `shared_preferences`, and session cleanup |
| Refresh tokens | Coordinated token refresh and one retry after an authenticated request returns 401 |
| Sample API | An example model, remote source, repository, ViewModel, and screen |

Authentication requires API support. Refresh tokens require authentication.
Public APIs can use API support without authentication.

Token storage uses `SharedPreferencesAsync`. Preferences are not encrypted;
session cleanup removes only the access and refresh tokens and preserves other
preferences. See the [shared_preferences documentation](https://pub.dev/packages/shared_preferences).

## Useful commands

Run `gold_flutter help` to see all commands, or `gold_flutter help create` for
help with a specific command.

| Command | What it does | Where to run it |
| --- | --- | --- |
| `gold_flutter create` | Creates a new app | Parent folder for the new project |
| `gold_flutter doctor` | Checks Flutter, Dart, and Git | Anywhere |
| `gold_flutter arrange model` | Standardizes an existing model's parsing and member order | Inside a Flutter project |
| `gold_flutter optimize` | Runs dependency resolution, code generation, formatting, analysis, tests, and audits | Inside a Flutter project |
| `gold_flutter add amount-formatter` | Adds a tested money-formatting utility | Inside a Flutter project |
| `gold_flutter docs` | Generates project documentation | Inside a Flutter project |

For commands that change an existing project, run from its root (the folder
with `pubspec.yaml`) or a folder inside it. Use `--dry-run` to preview changes;
use `--yes` to apply without an interactive confirmation.

```bash
# Preview a model update.
gold_flutter arrange model --path lib/domain/models/report_model.dart --dry-run

# Preview the project checks.
gold_flutter optimize --dry-run

# Add the money formatter with Nigerian defaults (en_NG, ₦).
gold_flutter add amount-formatter --yes

# Preview generated documentation.
gold_flutter docs --dry-run
```

`optimize` checks project health; it does not automatically tune runtime
performance. The amount formatter is available as
`MoneyFormatter.format(1200)` in `lib/core/utils/money_formatter.dart`.

Detailed options and limits:
[command help](docs/commands/help.md),
[model arranger](docs/commands/arrange-model.md),
[optimize](docs/commands/optimize.md),
[amount formatter](docs/commands/amount-formatter.md), and
[project docs](docs/commands/docs.md).

## Create an app from a script

Use `--yes` with explicit options to skip the wizard:

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
explicitly disable a feature.

## PATH setup

On macOS or Linux, add this line to your shell startup file (`~/.zshrc` or
`~/.bashrc`), then restart the terminal:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

On Windows, add this directory to your user `Path`, then restart the terminal:

```text
%LOCALAPPDATA%\Pub\Cache\bin
```

Optional convenience installers are available for
[macOS/Linux](scripts/install.sh) and [Windows PowerShell](scripts/install.ps1).
Review a downloaded script before running it.

## Update or uninstall

Run these commands from any folder:

```bash
gold_flutter check-update
gold_flutter update
gold_flutter uninstall
```

Before `gold_flutter create` starts, the CLI checks GitHub's `main` branch
for a newer commit and shows `gold_flutter update` when an update is available.
This detects changes even when the package version stays the same. Updates are
optional: ignore the notice and continue creating with your installed version.
An unavailable check (offline, timeout, or rate limit) also allows creation to
continue. The entire check has a 1.8-second deadline.

Skip the automatic check for one creation:

```bash
gold_flutter create --no-update-check
```

Or set `GOLD_FLUTTER_NO_UPDATE_CHECK=1` in your environment. Automatic checks
are skipped in CI. An explicit `gold_flutter check-update` still checks and
returns a nonzero exit code if the installation cannot be identified or GitHub
is unavailable. Local builds ahead of GitHub are identified without prompting
for a downgrade; diverged histories are reported separately.

`gold_flutter update` runs the installation command again using the current
Dart executable and your existing Pub cache (`PUB_CACHE`, when set):

```bash
dart pub global activate --source git --git-ref main \
  https://github.com/crisantus/gold-flutter.git
```

Existing apps keep their generated code. To change an existing app, run the
relevant project command and review its plan.

`gold_flutter uninstall` removes only the globally activated CLI. It keeps
your Flutter projects, app dependencies, and generated project guides. The
manual fallback also works with older CLI versions:

```bash
dart pub global deactivate gold_flutter
```

## Contribute

To work on the generator locally:

```bash
git clone https://github.com/crisantus/gold-flutter.git
cd gold-flutter
dart pub get --enforce-lockfile
dart analyze
dart test
```

Keep the lockfile enforced when checking Dart 3.5 compatibility. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the development and contribution workflow.

Templates use placeholders and example URLs. Keep credentials, tokens, signing
files, and production configuration out of version control.

## License

[MIT](LICENSE.md).
