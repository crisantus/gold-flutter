import 'package:gold_flutter/src/amount/amount_formatter_answers_collector.dart';
import 'package:test/test.dart';

import '../../support/fake_prompt_io.dart';

void main() {
  test('collects visible defaults', () {
    final answers = AmountFormatterAnswersCollector(
      io: FakePromptIO(['', '', '', '', '']),
    ).collect();

    expect(answers.locale, 'en_NG');
    expect(answers.symbol, '₦');
    expect(answers.decimalDigits, 2);
    expect(answers.useGrouping, isTrue);
    expect(answers.hiddenText, '₦ •••••');
  });

  test('re-prompts invalid digits and accepts custom values', () {
    final io = FakePromptIO(['en_US', r'$', '9', '2', 'n', r'$ hidden']);

    final answers = AmountFormatterAnswersCollector(io: io).collect();

    expect(answers.locale, 'en_US');
    expect(answers.symbol, r'$');
    expect(answers.decimalDigits, 2);
    expect(answers.useGrouping, isFalse);
    expect(answers.hiddenText, r'$ hidden');
    expect(io.output.join('\n'), contains('between 0 and 6'));
  });
}
