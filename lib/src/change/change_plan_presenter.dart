import '../prompts/prompt_io.dart';
import 'change_plan.dart';

/// Writes a deterministic preview of a [ChangePlan] and confirms its use.
final class ChangePlanPresenter {
  const ChangePlanPresenter({required PromptIO io}) : _io = io;

  final PromptIO _io;

  void print(ChangePlan plan) {
    _io.writeLine(plan.summary);
    _writeFiles(plan, FileChangeKind.create, 'Create');
    _writeFiles(plan, FileChangeKind.modify, 'Modify');
    if (plan.commands.isNotEmpty) {
      _io.writeLine('Run');
      for (final command in plan.commands) {
        final invocation = [command.executable, ...command.arguments].join(' ');
        _io.writeLine('  $invocation — ${command.reason}');
      }
    }
    if (plan.snapshotRoots.isNotEmpty) {
      _io.writeLine('Snapshot');
      for (final root in plan.snapshotRoots) {
        _io.writeLine('  $root');
      }
    }
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
      _io.writeLine('  ${file.relativePath} — ${file.reason}');
    }
  }
}
