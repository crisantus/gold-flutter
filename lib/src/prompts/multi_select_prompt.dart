enum MultiSelectKey { up, down, toggle, toggleAll, confirm }

final class MultiSelectOption {
  const MultiSelectOption({required this.value, required this.label});

  final String value;
  final String label;
}

final class MultiSelectState {
  MultiSelectState({
    required List<MultiSelectOption> options,
    required Set<String> initiallySelected,
  })  : options = List.unmodifiable(options),
        _selected = {...initiallySelected} {
    if (options.isEmpty) {
      throw ArgumentError.value(options, 'options', 'Must not be empty.');
    }
  }

  final List<MultiSelectOption> options;
  final Set<String> _selected;
  int focusedIndex = 0;

  Set<String> get selected => Set.unmodifiable(_selected);

  bool handle(MultiSelectKey key) {
    switch (key) {
      case MultiSelectKey.up:
        focusedIndex = (focusedIndex - 1) % options.length;
      case MultiSelectKey.down:
        focusedIndex = (focusedIndex + 1) % options.length;
      case MultiSelectKey.toggle:
        final value = options[focusedIndex].value;
        _selected.contains(value)
            ? _selected.remove(value)
            : _selected.add(value);
      case MultiSelectKey.toggleAll:
        if (_selected.length == options.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(options.map((option) => option.value));
        }
      case MultiSelectKey.confirm:
        return _selected.isNotEmpty;
    }
    return false;
  }
}

abstract interface class MultiSelectPromptIO {
  Set<String>? selectMany({
    required String title,
    required List<MultiSelectOption> options,
    required Set<String> initiallySelected,
  });
}
