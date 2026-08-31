# Contributing

Thank you for improving Gold Flutter.

## Local setup

```bash
git clone https://github.com/crisantus/gold-flutter.git
cd gold-flutter
dart pub get
git switch -c feat/describe-the-change
```

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
3. Open a pull request from the feature branch.
4. Merge only after CI passes.
5. Tag a verified release, for example `0.1.0`.

Users receive the latest version by running the activation command from the
README again.

