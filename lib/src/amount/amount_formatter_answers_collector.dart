import '../prompts/prompt_io.dart';
import 'amount_formatter_answers.dart';

final class AmountFormatterAnswersCollector {
  const AmountFormatterAnswersCollector({required PromptIO io}) : _io = io;

  final PromptIO _io;

  AmountFormatterAnswers collect() {
    final defaults = AmountFormatterAnswers.defaults();
    final locale = _text('Locale [${defaults.locale}]: ', defaults.locale);
    final symbol =
        _text('Currency symbol [${defaults.symbol}]: ', defaults.symbol);
    final decimalDigits = _digits(defaults.decimalDigits);
    final useGrouping = _yesNo(
      'Use grouped thousands? [Y/n]: ',
      defaults.useGrouping,
    );
    final hiddenText = _text(
      'Hidden balance text [${defaults.hiddenText}]: ',
      defaults.hiddenText,
    );
    return AmountFormatterAnswers(
      locale: locale,
      symbol: symbol,
      decimalDigits: decimalDigits,
      useGrouping: useGrouping,
      hiddenText: hiddenText,
    );
  }

  String _text(String prompt, String defaultValue) {
    while (true) {
      _io.write(prompt);
      final value = _read().trim();
      try {
        return AmountFormatterAnswers(
          locale: value.isEmpty ? defaultValue : value,
          symbol: 'x',
          decimalDigits: 0,
          useGrouping: true,
          hiddenText: 'x',
        ).locale;
      } on ArgumentError catch (error) {
        _io.writeLine(error.message);
      }
    }
  }

  int _digits(int defaultValue) {
    while (true) {
      _io.write('Decimal digits [$defaultValue]: ');
      final value = _read().trim();
      final parsed = value.isEmpty ? defaultValue : int.tryParse(value);
      if (parsed != null && parsed >= 0 && parsed <= 6) {
        return parsed;
      }
      _io.writeLine('Decimal digits must be between 0 and 6.');
    }
  }

  bool _yesNo(String prompt, bool defaultValue) {
    while (true) {
      _io.write(prompt);
      switch (_read().trim().toLowerCase()) {
        case '':
          return defaultValue;
        case 'y':
        case 'yes':
          return true;
        case 'n':
        case 'no':
          return false;
        default:
          _io.writeLine('Enter yes or no.');
      }
    }
  }

  String _read() {
    final value = _io.readLine();
    if (value == null) {
      throw const FormatException(
        'Input ended before amount formatter setup was complete.',
      );
    }
    return value;
  }
}
