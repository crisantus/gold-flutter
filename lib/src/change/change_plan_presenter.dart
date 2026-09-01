import '../prompts/prompt_io.dart';
import 'change_plan.dart';
import 'change_report.dart';

/// Writes a deterministic preview of a [ChangePlan] and confirms its use.
final class ChangePlanPresenter {
  const ChangePlanPresenter({required PromptIO io}) : _io = io;

  final PromptIO _io;

  void print(ChangePlan plan) {
    _io.writeLine(_quoted(plan.summary));
    if (plan.notices.isNotEmpty) {
      _io.writeLine('Notice');
      for (final notice in plan.notices) {
        _io.writeLine('  ${_quoted(notice.message)}');
      }
    }
    _writeFiles(plan, FileChangeKind.create, 'Create');
    _writeFiles(plan, FileChangeKind.modify, 'Modify');
    if (plan.preserved.isNotEmpty) {
      _io.writeLine('Preserved');
      for (final entry in plan.preserved) {
        _io.writeLine(
          '  ${_quoted(entry.subject)} — ${_quoted(entry.reason)}',
        );
      }
    }
    if (plan.commands.isNotEmpty) {
      _io.writeLine('Run');
      for (final command in plan.commands) {
        final invocation = [
          command.executable,
          ...command.arguments,
        ].map(_quoted).join(' ');
        _io.writeLine('  $invocation — ${_quoted(command.reason)}');
      }
    }
    if (plan.snapshotRoots.isNotEmpty) {
      _io.writeLine('Snapshot');
      for (final root in plan.snapshotRoots) {
        _io.writeLine('  ${_quoted(root)}');
      }
    }
  }

  void printReport(
    ChangeReport report, {
    Iterable<PlannedPreservation> preserved = const [],
  }) {
    final preservedEntries = List<PlannedPreservation>.of(preserved);
    _io.writeLine('Final report');
    _writeReportPaths('Created', report.created);
    _writeReportPaths('Modified', report.modified);
    if (preservedEntries.isNotEmpty) {
      _io.writeLine('Preserved');
      for (final entry in preservedEntries) {
        _io.writeLine(
          '  ${_quoted(entry.subject)} — ${_quoted(entry.reason)}',
        );
      }
    }
    _writeReportPaths('Skipped', report.skipped);
  }

  bool confirm({required bool assumeYes, required bool dryRun}) {
    if (dryRun) {
      _io.writeLine('No files have been changed.');
      return false;
    }
    if (assumeYes) {
      return true;
    }

    while (true) {
      _io.write('Apply these changes? [Y/n]: ');
      final answer = _io.readLine();
      if (answer == null) {
        return false;
      }
      switch (answer.trim().toLowerCase()) {
        case '':
        case 'y':
        case 'yes':
          return true;
        case 'n':
        case 'no':
          return false;
      }
    }
  }

  void _writeFiles(ChangePlan plan, FileChangeKind kind, String heading) {
    final files = plan.files.where((file) => file.kind == kind);
    if (files.isEmpty) {
      return;
    }
    _io.writeLine(heading);
    for (final file in files) {
      _io.writeLine(
        '  ${_quoted(file.relativePath)} — ${_quoted(file.reason)}',
      );
    }
  }

  void _writeReportPaths(String heading, Iterable<String> paths) {
    final entries = List<String>.of(paths);
    if (entries.isEmpty) {
      return;
    }
    _io.writeLine(heading);
    for (final path in entries) {
      _io.writeLine('  ${_quoted(path)}');
    }
  }

  static String _quoted(String value) {
    final escaped = StringBuffer("'");
    for (final rune in value.runes) {
      switch (rune) {
        case 0x08:
          escaped.write(r'\b');
        case 0x09:
          escaped.write(r'\t');
        case 0x0a:
          escaped.write(r'\n');
        case 0x0b:
          escaped.write(r'\v');
        case 0x0c:
          escaped.write(r'\f');
        case 0x0d:
          escaped.write(r'\r');
        case 0x22:
          escaped.write(r'\"');
        case 0x27:
          escaped.write(r"\'");
        case 0x5c:
          escaped.write(r'\\');
        case >= 0 && <= 0x1f:
          escaped.write(r'\x');
          escaped.write(rune.toRadixString(16).padLeft(2, '0'));
        case >= 0x7f && <= 0x9f:
          escaped.write(r'\x');
          escaped.write(rune.toRadixString(16).padLeft(2, '0'));
        case 0x2028:
          escaped.write(r'\u2028');
        case 0x2029:
          escaped.write(r'\u2029');
        default:
          escaped.writeCharCode(rune);
      }
    }
    escaped.write("'");
    return escaped.toString();
  }
}
