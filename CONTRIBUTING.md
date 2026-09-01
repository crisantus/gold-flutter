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
dart format --output=none --set-exit-if-changed bin lib test
dart analyze
dart test
```

Changes to generated Flutter code must also generate and verify the supported
project variants with `flutter analyze` and `flutter test`.

## Updating the public generator

1. Change templates and focused tests together.
2. Update `README.md` and `CHANGELOG.md` when behavior changes.
3. Review the complete local `main` diff, or open a pull request when using a
   contributor branch.
4. Push only after local verification and explicit approval; wait for CI.
5. Tag a verified release only after separate release approval.

Users receive the latest version by running the activation command from the
README again.
