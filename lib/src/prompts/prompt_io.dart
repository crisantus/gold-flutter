import 'dart:io';

import 'multi_select_prompt.dart';

final class UserCancelledException implements Exception {
  const UserCancelledException();
}

abstract interface class PromptIO {
  String? readLine();
  void write(String message);
  void writeLine(String message);
}

final class ConsolePromptIO implements PromptIO, MultiSelectPromptIO {
  const ConsolePromptIO();

  @override
  String? readLine() => stdin.readLineSync();

  @override
  void write(String message) => stdout.write(message);

  @override
  void writeLine(String message) => stdout.writeln(message);

  @override
  Set<String>? selectMany({
    required String title,
    required List<MultiSelectOption> options,
    required Set<String> initiallySelected,
  }) {
    if (!stdin.hasTerminal ||
        !stdout.hasTerminal ||
        !stdout.supportsAnsiEscapes) {
      return null;
    }

    final state = MultiSelectState(
      options: options,
      initiallySelected: initiallySelected,
    );
    final previousLineMode = stdin.lineMode;
    final previousEchoMode = stdin.echoMode;
    try {
      stdin
        ..lineMode = false
        ..echoMode = false;
      stdout
        ..writeln(title)
        ..writeln('↑/↓ Move • Space Toggle • A All • Enter Confirm • Q Cancel')
        ..writeln()
        ..write('\x1B[?25l');
      _renderOptions(state);

      while (true) {
        final key = _readSelectionKey();
        if (key == null) continue;
        if (state.handle(key)) return state.selected;
        if (key == MultiSelectKey.confirm) {
          stdout.write('\x07');
          continue;
        }
        stdout.write('\x1B[${options.length}A');
        _renderOptions(state);
      }
    } finally {
      stdin
        ..lineMode = previousLineMode
        ..echoMode = previousEchoMode;
      stdout
        ..write('\x1B[?25h')
        ..writeln();
    }
  }

  void _renderOptions(MultiSelectState state) {
    for (var index = 0; index < state.options.length; index++) {
      final option = state.options[index];
      final cursor = index == state.focusedIndex ? '❯' : ' ';
      final checked = state.selected.contains(option.value) ? '✓' : ' ';
      stdout.writeln('\x1B[2K\r$cursor [$checked] ${option.label}');
    }
  }

  MultiSelectKey? _readSelectionKey() {
    final byte = stdin.readByteSync();
    switch (byte) {
      case 3:
      case 4:
      case 113:
      case 81:
        throw const UserCancelledException();
      case 10:
      case 13:
        return MultiSelectKey.confirm;
      case 32:
        return MultiSelectKey.toggle;
      case 97:
      case 65:
        return MultiSelectKey.toggleAll;
      case 27:
        final bracket = stdin.readByteSync();
        final direction = stdin.readByteSync();
        if (bracket != 91) return null;
        if (direction == 65) return MultiSelectKey.up;
        if (direction == 66) return MultiSelectKey.down;
        return null;
      default:
        return null;
    }
  }
}
