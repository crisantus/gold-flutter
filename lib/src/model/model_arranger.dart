import 'dart:io';

import 'package:path/path.dart' as p;

import '../change/change_plan.dart';
import '../project/project_inspection.dart';
import 'dart_model_parser.dart';
import 'eyeask_model_renderer.dart';
import 'model_test_renderer.dart';

final class ModelArrangementException implements Exception {
  const ModelArrangementException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Builds the complete transactional plan for arranging one supported model.
final class ModelArranger {
  const ModelArranger({
    this.parser = const DartModelParser(),
    this.renderer = const EyeAskModelRenderer(),
    this.testRenderer = const ModelTestRenderer(),
  });

  final DartModelParser parser;
  final EyeAskModelRenderer renderer;
  final ModelTestRenderer testRenderer;

  Future<ChangePlan> plan({
    required ProjectInspection project,
    required String path,
    required bool addCopyWith,
    required bool addTest,
  }) async {
    final modelPath = await _validatedModelPath(project.root, path);
    final source = await _readFile(modelPath.file, modelPath.relativePath);
    final parsed = parser.parse(source, modelPath.relativePath);
    if (!parsed.isSafe) {
      throw ModelArrangementException(parsed.diagnostics.join('\n'));
    }

    final files = <PlannedFileChange>[
      PlannedFileChange(
        relativePath: modelPath.relativePath,
        content: renderer.render(
          parsed.spec!,
          addCopyWith: addCopyWith,
        ),
        kind: FileChangeKind.modify,
        reason: 'Arrange models using the EyeAsk standard',
      ),
    ];
    String? focusedTestPath;
    var preservedTest = false;
    if (addTest) {
      focusedTestPath = testRenderer.testPathFor(modelPath.relativePath);
      final testTarget = await _validatedProjectTarget(
        project.root,
        focusedTestPath,
      );
      final type = await FileSystemEntity.type(
        testTarget.path,
        followLinks: false,
      );
      final kind = switch (type) {
        FileSystemEntityType.notFound => FileChangeKind.create,
        FileSystemEntityType.file => FileChangeKind.modify,
        _ => throw ModelArrangementException(
            'Focused test path is not a regular file: $focusedTestPath',
          ),
      };
      if (kind == FileChangeKind.modify) {
        final existing = await _readFile(testTarget, focusedTestPath);
        if (_firstLine(existing) != ModelTestRenderer.ownershipMarker) {
          preservedTest = true;
        }
      }
      if (!preservedTest) {
        final modelImport = p.posix.join(
          'package:${project.projectName}',
          modelPath.relativePath.substring('lib/'.length),
        );
        files.add(
          PlannedFileChange(
            relativePath: focusedTestPath,
            content: testRenderer.render(
              parsed.spec!,
              modelImport: modelImport,
            ),
            kind: kind,
            reason: 'Add defensive tests for the arranged model',
          ),
        );
      }
    }

    final commands = <PlannedCommand>[
      PlannedCommand(
        executable: 'dart',
        arguments: ['format', ...files.map((file) => file.relativePath)],
        reason: 'Format arranged model files',
        mutatesFiles: true,
      ),
      PlannedCommand(
        executable: 'flutter',
        arguments: const ['analyze'],
        reason: 'Analyze the arranged project',
        mutatesFiles: false,
      ),
      if (focusedTestPath != null && !preservedTest)
        PlannedCommand(
          executable: 'flutter',
          arguments: ['test', focusedTestPath],
          reason: 'Run the generated model test',
          mutatesFiles: false,
        ),
    ];
    final summary = preservedTest
        ? 'Arrange ${modelPath.relativePath}. Preserve non-Gold test '
            '$focusedTestPath.'
        : 'Arrange ${modelPath.relativePath} using the EyeAsk standard.';
    return ChangePlan(
      summary: summary,
      projectRoot: project.root,
      files: files,
      commands: commands,
    );
  }
}

final class _ModelPath {
  const _ModelPath({required this.file, required this.relativePath});

  final File file;
  final String relativePath;
}

Future<_ModelPath> _validatedModelPath(
  Directory projectRoot,
  String input,
) async {
  if (input.trim().isEmpty || _containsTraversal(input)) {
    throw ModelArrangementException('Unsafe model path: $input');
  }
  final platformInput =
      input.replaceAll('/', p.separator).replaceAll('\\', p.separator);
  final root = p.normalize(p.absolute(projectRoot.path));
  final target = p.normalize(
    p.isAbsolute(platformInput) ? platformInput : p.join(root, platformInput),
  );
  if (!p.isWithin(root, target)) {
    throw ModelArrangementException(
      'Model path must stay within the project: $input',
    );
  }
  final relativePath = _portableRelative(target, root);
  if (!relativePath.startsWith('lib/domain/models/') ||
      p.posix.extension(relativePath) != '.dart') {
    throw ModelArrangementException(
      'Model must be a Dart file under lib/domain/models/: $input',
    );
  }
  final file = await _validatedProjectTarget(projectRoot, relativePath);
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.file) {
    throw ModelArrangementException(
      'Model path must be an existing Dart file: $relativePath',
    );
  }
  return _ModelPath(file: file, relativePath: relativePath);
}

Future<File> _validatedProjectTarget(
  Directory projectRoot,
  String relativePath,
) async {
  final root = p.normalize(p.absolute(projectRoot.path));
  final target = p.normalize(
    p.joinAll([root, ...p.posix.split(relativePath)]),
  );
  if (!p.isWithin(root, target)) {
    throw ModelArrangementException(
      'Path must stay within the project: $relativePath',
    );
  }
  if (await FileSystemEntity.isLink(root)) {
    throw ModelArrangementException(
      'Project root must not be a symbolic link: ${projectRoot.path}',
    );
  }
  var current = root;
  for (final segment in p.posix.split(relativePath)) {
    current = p.join(current, segment);
    if (await FileSystemEntity.isLink(current)) {
      throw ModelArrangementException(
        'Path contains a symbolic link: $relativePath',
      );
    }
  }
  return File(target);
}

Future<String> _readFile(File file, String displayPath) async {
  try {
    return await file.readAsString();
  } on FileSystemException catch (error) {
    throw ModelArrangementException(
      'Unable to read $displayPath: ${error.message}',
    );
  }
}

bool _containsTraversal(String value) {
  final portable = value.replaceAll('\\', '/');
  return p.posix.split(portable).contains('..');
}

String _portableRelative(String target, String root) =>
    p.posix.joinAll(p.split(p.relative(target, from: root)));

String _firstLine(String value) {
  final newline = value.indexOf('\n');
  final line = newline == -1 ? value : value.substring(0, newline);
  return line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
}
