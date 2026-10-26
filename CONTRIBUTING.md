# Contributing

Thank you for improving Gold Flutter.

## Local setup

```bash
git clone https://github.com/crisantus/gold-flutter.git
cd gold-flutter
dart pub get --enforce-lockfile
```

Gold Flutter currently supports Dart SDK `>=3.5.0 <4.0.0`. Keep the committed
lockfile enforced because its development-tool pins preserve the Dart 3.5
dependency floor.

During the `0.2.0-dev` test-and-debug cycle, maintainers may commit verified
local work directly to `main`. A short-lived feature branch is optional for
local work and remains useful for external pull requests.

## Verification

Run these checks before proposing a change:

```bash
dart format --output=none --set-exit-if-changed bin lib test tool
dart analyze
dart test
bash -n scripts/install.sh
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ci.yml')"
```

For CLI installation changes, run the isolated Dart Pub smoke test:

```bash
dart run tool/verify_cli_lifecycle.dart
# Also exercise the real update command against GitHub:
dart run tool/verify_cli_lifecycle.dart --live-update
```

It downloads dependencies into a temporary `PUB_CACHE`, verifies installed
Git revision metadata and same-version commit reactivation, then uninstalls
while comparing every existing fixture application file. Your normal global
installation is unchanged. The live option also activates GitHub `main`.

Changes to generated Flutter code must also generate and verify the supported
project variants with `flutter analyze` and `flutter test`.

## Updating the public generator

1. Change templates and focused tests together.
2. Update `README.md` and `CHANGELOG.md` when behavior changes.
3. Review the complete local `main` diff, or open a pull request when using a
   contributor branch.
4. Push only after local verification and explicit approval; wait for CI.
5. Tag a verified release only after separate release approval.

Linux CI runs the full suite and exercises every assistant command in a
disposable Flutter application. Windows parses the installer and runs
platform-neutral safety tests.

Users receive optional notices before `create` and can run `gold_flutter update`
to activate the latest GitHub `main`. The manual activation command in the
README remains available for older installations.
