import 'dart:io';

import 'package:path/path.dart' as p;

import '../change/change_plan.dart';
import '../project/project_inspection.dart';
import 'documentation_manifest.dart';
import 'markdown_documentation_renderer.dart';
import 'project_documentation_scanner.dart';

final class DocumentationGenerator {
  const DocumentationGenerator({
    ProjectDocumentationScanner scanner = const ProjectDocumentationScanner(),
    MarkdownDocumentationRenderer renderer =
        const MarkdownDocumentationRenderer(),
  })  : _scanner = scanner,
        _renderer = renderer;

  static const manifestPath = 'docs/gold_flutter/.gold_flutter_docs.json';

  final ProjectDocumentationScanner _scanner;
  final MarkdownDocumentationRenderer _renderer;

  Future<ChangePlan> plan(ProjectInspection project) async {
    final rendered = _renderer.render(await _scanner.scan(project));
    final manifestFile = File(p.join(project.root.path, manifestPath));
    final oldManifestContent =
        await manifestFile.exists() ? await manifestFile.readAsString() : null;
    final oldManifest = oldManifestContent == null
        ? DocumentationManifest(version: '0.2.0-dev', hashes: const {})
        : DocumentationManifest.decode(oldManifestContent);
    final files = <PlannedFileChange>[];
    final preserved = <PlannedPreservation>[];
    final nextHashes = <String, String>{};

    for (final entry in rendered.entries) {
      final target = File(p.join(project.root.path, entry.key));
      final current =
          await target.exists() ? await target.readAsString() : null;
      final manifestKey = p.basename(entry.key);
      if (!oldManifest.canUpdate(manifestKey, current)) {
        preserved.add(
          PlannedPreservation(
            subject: entry.key,
            reason: 'User-edited generated documentation is preserved.',
          ),
        );
        final oldHash = oldManifest.hashes[manifestKey];
        if (oldHash != null) nextHashes[manifestKey] = oldHash;
        continue;
      }
      files.add(
        PlannedFileChange(
          relativePath: entry.key,
          content: entry.value,
          kind: current == null ? FileChangeKind.create : FileChangeKind.modify,
          reason: current == null
              ? 'Create generated project documentation.'
              : 'Update Gold Flutter-owned project documentation.',
          precondition: current == null
              ? const TextFilePrecondition.absent()
              : TextFilePrecondition.exact(current),
        ),
      );
      nextHashes[manifestKey] = DocumentationManifest.sha256Of(entry.value);
    }

    final nextManifest = DocumentationManifest(
      version: '0.2.0-dev',
      hashes: nextHashes,
    ).encode();
    files.add(
      PlannedFileChange(
        relativePath: manifestPath,
        content: '$nextManifest\n',
        kind: oldManifestContent == null
            ? FileChangeKind.create
            : FileChangeKind.modify,
        reason: 'Record Gold Flutter documentation ownership hashes.',
        precondition: oldManifestContent == null
            ? const TextFilePrecondition.absent()
            : TextFilePrecondition.exact(oldManifestContent),
      ),
    );
    return ChangePlan(
      summary: 'Generate documentation for ${project.projectName}',
      projectRoot: project.root,
      files: files,
      preserved: preserved,
      commands: [
        PlannedCommand(
          executable: 'flutter',
          arguments: const ['analyze'],
          reason: 'Verify the documented Flutter project.',
          mutatesFiles: false,
        ),
      ],
    );
  }
}
