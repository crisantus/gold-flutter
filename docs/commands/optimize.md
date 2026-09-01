# Optimize

```bash
gold_flutter optimize --dry-run
gold_flutter optimize --yes
```

Flags: `--dry-run`, `--yes`. Stages are dependency resolution, conditional
build runner, formatting, analysis, tests, and a read-only asset/generated-file
audit. Execution stops on the first failed tool and restores snapshotted source
files. External caches are not rolled back. This command does not rewrite
business logic or claim automatic runtime-performance improvements.
