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
dart pub global activate --source git https://github.com/crisantus/gold-flutter.git
```

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

## Update

After improvements are pushed to this repository, install the newest version
with the same command:

```bash
dart pub global activate --source git https://github.com/crisantus/gold-flutter.git
```

Generator updates affect newly created projects only. Existing Flutter apps
are never rewritten automatically.

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

Make changes on a feature branch, keep tests green, and open a pull request.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the release workflow.

## Security

Templates contain placeholders and example URLs only. Never commit API keys,
tokens, signing certificates, service-account files, production `.env` files,
or real credentials to this public repository or to a generated application.

## License

Gold Flutter is available under the [MIT License](LICENSE.md).
