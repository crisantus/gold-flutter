import 'dart:io';

import 'package:path/path.dart' as p;

enum FileChangeKind { create, modify }

enum TextFilePreconditionKind { absent, exactContent }

/// An opt-in preview-time condition for a planned UTF-8 text-file change.
final class TextFilePrecondition {
  const TextFilePrecondition.absent()
      : kind = TextFilePreconditionKind.absent,
        expectedContent = null;

  const TextFilePrecondition.exact(String content)
      : kind = TextFilePreconditionKind.exactContent,
        expectedContent = content;

  final TextFilePreconditionKind kind;
  final String? expectedContent;
}

final class PlannedFileChange {
  const PlannedFileChange({
    required this.relativePath,
    required this.content,
    required this.kind,
    required this.reason,
    this.precondition,
  });

  final String relativePath;
  final String content;
  final FileChangeKind kind;
  final String reason;
  final TextFilePrecondition? precondition;
}

final class PlannedCommand {
  PlannedCommand({
    required this.executable,
    required List<String> arguments,
    required this.reason,
    required this.mutatesFiles,
  }) : _arguments = List.unmodifiable(arguments);

  final String executable;
  final List<String> _arguments;
  final String reason;
  final bool mutatesFiles;

  List<String> get arguments => _arguments;
}

final class PlannedNotice {
  const PlannedNotice(this.message);

  final String message;
}

final class PlannedPreservation {
  const PlannedPreservation({
    required this.subject,
    required this.reason,
  });

  final String subject;
  final String reason;
}

final class ChangePlan {
  ChangePlan({
    required this.summary,
    required this.projectRoot,
    Iterable<PlannedFileChange> files = const [],
    Iterable<PlannedCommand> commands = const [],
    Iterable<String> snapshotRoots = const [],
    Iterable<PlannedNotice> notices = const [],
    Iterable<PlannedPreservation> preserved = const [],
  })  : files = List.unmodifiable(
          _normalizeAndValidateFiles(files),
        ),
        commands = List.unmodifiable(commands),
        snapshotRoots = List.unmodifiable(
          _normalizeAndValidateRoots(snapshotRoots),
        ),
        notices = List.unmodifiable(notices),
        preserved = List.unmodifiable(preserved);

  final String summary;
  final Directory projectRoot;
  final List<PlannedFileChange> files;
  final List<PlannedCommand> commands;
  final List<String> snapshotRoots;
  final List<PlannedNotice> notices;
  final List<PlannedPreservation> preserved;

  static List<PlannedFileChange> _normalizeAndValidateFiles(
    Iterable<PlannedFileChange> changes,
  ) {
    final normalized = <PlannedFileChange>[];
    final paths = <String>{};
    for (final change in changes) {
      final path = _validateRelativePath(change.relativePath);
      _validatePrecondition(change);
      if (!paths.add(path)) {
        throw ArgumentError('Duplicate planned file path: $path');
      }
      normalized.add(
        PlannedFileChange(
          relativePath: path,
          content: change.content,
          kind: change.kind,
          reason: change.reason,
          precondition: change.precondition,
        ),
      );
    }
    return normalized;
  }

  static void _validatePrecondition(PlannedFileChange change) {
    final precondition = change.precondition;
    if (precondition == null) {
      return;
    }
    final coherent = switch ((change.kind, precondition.kind)) {
      (FileChangeKind.create, TextFilePreconditionKind.absent) => true,
      (FileChangeKind.modify, TextFilePreconditionKind.exactContent) => true,
      _ => false,
    };
    if (!coherent) {
      throw ArgumentError(
        'Text-file precondition ${precondition.kind.name} is not valid for '
        '${change.kind.name}: ${change.relativePath}',
      );
    }
  }

  static List<String> _normalizeAndValidateRoots(Iterable<String> roots) {
    final normalized = <String>[];
    final paths = <String>{};
    for (final root in roots) {
      final path = _validateRelativePath(root);
      if (!paths.add(path)) {
        throw ArgumentError('Duplicate snapshot root: $path');
      }
      normalized.add(path);
    }
    return normalized;
  }

  static String normalizeRelativePath(String value) {
    final portable = value.replaceAll('\\', '/');
    final normalized = p.posix.normalize(portable);
    if (p.isAbsolute(value) ||
        p.posix.isAbsolute(value) ||
        p.windows.isAbsolute(value) ||
        p.posix.isAbsolute(portable) ||
        p.windows.isAbsolute(portable) ||
        RegExp(r'^[a-zA-Z]:').hasMatch(value) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        RegExp(r'(^|[\\/])\.\.([\\/]|$)').hasMatch(value)) {
      throw ArgumentError('Path must stay within project root: $value');
    }
    return normalized;
  }

  static String _validateRelativePath(String value) =>
      normalizeRelativePath(value);
}
