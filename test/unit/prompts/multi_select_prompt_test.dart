import 'package:gold_flutter/src/prompts/multi_select_prompt.dart';
import 'package:test/test.dart';

void main() {
  test('moves through options and toggles the focused selection', () {
    final state = MultiSelectState(
      options: const [
        MultiSelectOption(value: 'android', label: 'Android'),
        MultiSelectOption(value: 'ios', label: 'iOS'),
        MultiSelectOption(value: 'web', label: 'Web'),
      ],
      initiallySelected: const {'android', 'ios', 'web'},
    );

    state.handle(MultiSelectKey.down);
    state.handle(MultiSelectKey.toggle);

    expect(state.focusedIndex, 1);
    expect(state.selected, {'android', 'web'});
    expect(state.handle(MultiSelectKey.confirm), isTrue);
  });

  test('does not confirm an empty platform selection', () {
    final state = MultiSelectState(
      options: const [
        MultiSelectOption(value: 'android', label: 'Android'),
      ],
      initiallySelected: const {'android'},
    );

    state.handle(MultiSelectKey.toggle);

    expect(state.handle(MultiSelectKey.confirm), isFalse);
    expect(state.selected, isEmpty);
  });

  test('wraps keyboard navigation and can toggle every option', () {
    final state = MultiSelectState(
      options: const [
        MultiSelectOption(value: 'android', label: 'Android'),
        MultiSelectOption(value: 'ios', label: 'iOS'),
      ],
      initiallySelected: const {'android', 'ios'},
    );

    state.handle(MultiSelectKey.up);
    expect(state.focusedIndex, 1);

    state.handle(MultiSelectKey.toggleAll);
    expect(state.selected, isEmpty);
    state.handle(MultiSelectKey.toggleAll);
    expect(state.selected, {'android', 'ios'});
  });
}
