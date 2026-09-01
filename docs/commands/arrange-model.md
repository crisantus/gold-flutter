# Arrange model

Rewrites a supported file under `lib/domain/models/` into the defensive EyeAsk
member order while preserving safe custom code and envelope helpers.

Run it from the Flutter project root or any folder inside that project. The
`--path` value is easiest to understand when it is relative to the project
root. Preview with `--dry-run` before applying unfamiliar changes.

```bash
gold_flutter arrange model \
  --path lib/domain/models/report_model.dart \
  --copy-with \
  --test \
  --yes
```

Flags: `--path` (required), `--copy-with`, `--test`, `--dry-run`, `--yes`.
Supported fields include primitives, dates, same-file nested models, lists,
preservable enum converters, snake/camel JSON keys, and direct, `data`, or
`data.items` envelopes. Unsupported or ambiguous files are refused as a whole.
Formatting, analysis, or focused-test failure restores changed files.
