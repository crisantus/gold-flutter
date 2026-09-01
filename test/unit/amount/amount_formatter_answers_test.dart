import 'package:gold_flutter/src/amount/amount_formatter_answers.dart';
import 'package:test/test.dart';

void main() {
  test('uses Nigerian currency defaults', () {
    final answers = AmountFormatterAnswers.defaults();

    expect(answers.locale, 'en_NG');
    expect(answers.symbol, '₦');
    expect(answers.decimalDigits, 2);
    expect(answers.useGrouping, isTrue);
    expect(answers.hiddenText, '₦ •••••');
  });

  test('rejects empty control text and digits outside zero through six', () {
    expect(
      () => AmountFormatterAnswers(
        locale: 'en_NG',
        symbol: '₦',
        decimalDigits: 7,
        useGrouping: true,
        hiddenText: 'hidden',
      ),
      throwsArgumentError,
    );
    expect(
      () => AmountFormatterAnswers(
        locale: 'en_NG',
        symbol: '\n',
        decimalDigits: 2,
        useGrouping: true,
        hiddenText: 'hidden',
      ),
      throwsArgumentError,
    );
  });
}
