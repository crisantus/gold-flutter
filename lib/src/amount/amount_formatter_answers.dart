final class AmountFormatterAnswers {
  AmountFormatterAnswers({
    required String locale,
    required String symbol,
    required this.decimalDigits,
    required this.useGrouping,
    required String hiddenText,
  })  : locale = _text(locale, 'locale'),
        symbol = _text(symbol, 'symbol'),
        hiddenText = _text(hiddenText, 'hiddenText') {
    if (decimalDigits < 0 || decimalDigits > 6) {
      throw ArgumentError.value(
        decimalDigits,
        'decimalDigits',
        'must be between 0 and 6',
      );
    }
  }

  factory AmountFormatterAnswers.defaults() => AmountFormatterAnswers(
        locale: 'en_NG',
        symbol: '₦',
        decimalDigits: 2,
        useGrouping: true,
        hiddenText: '₦ •••••',
      );

  final String locale;
  final String symbol;
  final int decimalDigits;
  final bool useGrouping;
  final String hiddenText;

  static String _text(String value, String name) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(trimmed)) {
      throw ArgumentError.value(
        value,
        name,
        'must be non-empty text without control characters',
      );
    }
    return trimmed;
  }
}
