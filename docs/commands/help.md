# Find commands and choose the correct folder

Run Gold Flutter with no command whenever you forget what is available:

```bash
gold_flutter
```

`gold_flutter help` prints the same catalog. It includes a brief description
and the correct working directory for every command.

## Detailed help

```bash
gold_flutter help create
gold_flutter help check-update
gold_flutter help update
gold_flutter help uninstall
gold_flutter help doctor
gold_flutter help arrange model
gold_flutter help optimize
gold_flutter help add amount-formatter
gold_flutter help docs
```

You can also place `--help` after a command:

```bash
gold_flutter create --help
gold_flutter arrange model --help
gold_flutter optimize --help
```

## Working directories

| Command | Run from |
| --- | --- |
| `create` | The parent folder that should contain the generated project. |
| `doctor` | Anywhere. |
| `check-update` | Anywhere. |
| `update` | Anywhere; updates only the CLI. |
| `uninstall` | Anywhere; removes only the CLI. |
| `arrange model` | The Flutter project root or any folder inside it. |
| `optimize` | The Flutter project root or any folder inside it. |
| `add amount-formatter` | The Flutter project root or any folder inside it. |
| `docs` | The Flutter project root or any folder inside it. |

The project root is the folder containing the Flutter application's
`pubspec.yaml`. Project commands search upward from the current directory, so
they also work from a nested folder such as `lib/presentation/screens/`.
Running from the root remains recommended because relative paths and command
output are easier to follow.

## CLI updates and removal

`create` shows optional GitHub update notices before starting. Use
`gold_flutter update` to install the latest CLI from `main`, or ignore the
notice and continue. Skip automatic checks with `create --no-update-check`
or `GOLD_FLUTTER_NO_UPDATE_CHECK=1`; CI skips them automatically. Offline or
failed checks do not block creation. `gold_flutter check-update` performs an
explicit check and reports failure with a nonzero exit code.

`gold_flutter uninstall` delegates to `dart pub global deactivate gold_flutter`.
Both lifecycle commands preserve existing applications and their dependencies.
See the [installation and update guide](../../README.md#update-or-uninstall)
for manual commands and details.
