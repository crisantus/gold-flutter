# Amount formatter

```bash
gold_flutter add amount-formatter --yes
```

Flags: `--locale`, `--symbol`, `--decimal-digits` (0–6), `--grouping` or
`--no-grouping`, `--hidden-text`, `--dry-run`, and `--yes`. Defaults are
`en_NG`, `₦`, 2 digits, grouping enabled, and `₦ •••••`. Gold Flutter updates
only its owned files and refuses unowned conflicts. Dependency or verification
failure restores `pubspec` state and generated files.

```dart
Text(MoneyFormatter.format(1200));
```
