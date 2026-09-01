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
| `arrange model` | The Flutter project root or any folder inside it. |
| `optimize` | The Flutter project root or any folder inside it. |
| `add amount-formatter` | The Flutter project root or any folder inside it. |
| `docs` | The Flutter project root or any folder inside it. |

The project root is the folder containing the Flutter application's
`pubspec.yaml`. Project commands search upward from the current directory, so
they also work from a nested folder such as `lib/presentation/screens/`.
Running from the root remains recommended because relative paths and command
output are easier to follow.
