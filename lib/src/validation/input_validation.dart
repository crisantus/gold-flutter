import '../config/project_answers.dart';

abstract final class InputValidation {
  static final RegExp _projectNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');
  static final RegExp _applicationIdSegment = RegExp(r'^[a-z][a-z0-9_]*$');

  static String deriveProjectName(String displayName) {
    var derived = displayName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (derived.isEmpty) {
      throw const FormatException(
        'The display name must contain at least one letter or number.',
      );
    }
    if (RegExp(r'^[0-9]').hasMatch(derived)) {
      derived = 'app_$derived';
    }
    return projectName(derived);
  }

  static String projectName(String value) {
    final normalized = value.trim();
    if (!_projectNamePattern.hasMatch(normalized)) {
      throw const FormatException(
        'Use lowercase snake_case beginning with a letter.',
      );
    }
    return normalized;
  }

  static String applicationId(String value) {
    final normalized = value.trim();
    final segments = normalized.split('.');
    if (segments.length < 3 ||
        segments.any((segment) => !_applicationIdSegment.hasMatch(segment))) {
      throw const FormatException(
        'Use at least three lowercase reverse-domain segments, such as com.company.app.',
      );
    }
    return normalized;
  }

  static Uri httpUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
        'Enter a complete HTTP(S) URL, such as https://api.company.com.',
      );
    }
    return uri;
  }

  static Set<TargetPlatform> platforms(String value) {
    final names = value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      throw const FormatException('Select at least one target platform.');
    }

    final available = {
      for (final platform in TargetPlatform.values) platform.name: platform
    };
    final selected = <TargetPlatform>{};
    for (final name in names) {
      final platform = available[name];
      if (platform == null) {
        throw FormatException(
          'Unknown platform "$name". Use ${available.keys.join(', ')}.',
        );
      }
      selected.add(platform);
    }
    return selected;
  }
}
