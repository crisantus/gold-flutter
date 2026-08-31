abstract final class TextEscaping {
  static String dartSingleQuoted(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');

  static String yamlDoubleQuoted(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String xmlText(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String xmlAttribute(String value) =>
      xmlText(value).replaceAll('"', '&quot;');

  static String htmlAttribute(String value) =>
      xmlAttribute(value).replaceAll("'", '&#39;');

  static String cppString(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
