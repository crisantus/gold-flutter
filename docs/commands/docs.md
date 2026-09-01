# Generate docs

```bash
gold_flutter docs --dry-run
gold_flutter docs --yes
```

Flags: `--dry-run`, `--yes`. The generated Markdown covers architecture,
dependencies, routes, assets, models, and commands. A SHA-256 ownership
manifest permits repeatable updates while preserving user-modified files.
Dynamic or malformed facts are reported as unknown rather than invented. A
failed project analysis restores documentation changes.
