import 'dart:convert';

import 'package:crypto/crypto.dart';

final class DocumentationManifest {
  DocumentationManifest({
    required this.version,
    required Map<String, String> hashes,
  }) : hashes = Map.unmodifiable(Map.fromEntries(
          hashes.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)),
        ));

  final String version;
  final Map<String, String> hashes;

  static DocumentationManifest decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map ||
        value['generatorVersion'] is! String ||
        value['files'] is! Map) {
      throw const FormatException(
          'Invalid Gold Flutter documentation manifest.');
    }
    final files = <String, String>{};
    for (final entry in (value['files'] as Map).entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException(
            'Invalid Gold Flutter documentation manifest hash.');
      }
      files[entry.key as String] = entry.value as String;
    }
    return DocumentationManifest(
      version: value['generatorVersion'] as String,
      hashes: files,
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'generatorVersion': version,
        'files': hashes,
      });

  bool canUpdate(String path, String? currentContent) {
    if (currentContent == null) return true;
    final previous = hashes[path];
    return previous != null && previous == sha256Of(currentContent);
  }

  static String sha256Of(String content) =>
      sha256.convert(utf8.encode(content)).toString();
}
