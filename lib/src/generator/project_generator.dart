import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/project_answers.dart';
import '../platform/app_identity.dart';
import '../platform/platform_patcher.dart';
import '../process/process_executor.dart';
import 'flutter_creator.dart';
import 'project_verifier.dart';
import 'staging_area.dart';
import 'template_renderer.dart';

abstract interface class ProjectGenerator {
  Future<Directory> generate({
    required ProjectAnswers answers,
    required Directory destinationParent,
  });
}

final class PendingProjectGenerator implements ProjectGenerator {
  const PendingProjectGenerator();

  @override
  Future<Directory> generate({
    required ProjectAnswers answers,
    required Directory destinationParent,
  }) {
    throw const ProjectGenerationException(
      'Project rendering is not available in this development build yet.',
    );
  }
}

final class DefaultProjectGenerator implements ProjectGenerator {
  const DefaultProjectGenerator({
    required FlutterProjectCreator creator,
    required ProjectPlatformPatcher platformPatcher,
    required ProjectTemplateRenderer renderer,
    required ProjectVerifier verifier,
  })  : _creator = creator,
        _platformPatcher = platformPatcher,
        _renderer = renderer,
        _verifier = verifier;

  factory DefaultProjectGenerator.standard() {
    const executor = LocalProcessExecutor();
    return DefaultProjectGenerator(
      creator: const FlutterCreator(executor: executor),
      platformPatcher: const PlatformPatcher(),
      renderer: const TemplateRenderer(),
      verifier: const GeneratedProjectVerifier(executor: executor),
    );
  }

  final FlutterProjectCreator _creator;
  final ProjectPlatformPatcher _platformPatcher;
  final ProjectTemplateRenderer _renderer;
  final ProjectVerifier _verifier;

  @override
  Future<Directory> generate({
    required ProjectAnswers answers,
    required Directory destinationParent,
  }) async {
    final destination = Directory(
      p.join(destinationParent.absolute.path, answers.projectName),
    );
    final staging = await StagingArea.create(destination: destination);
    try {
      await _creator.create(answers: answers, output: staging.directory);
      await _platformPatcher.apply(
        projectRoot: staging.directory,
        identity: AppIdentity(
          displayName: answers.displayName,
          projectName: answers.projectName,
          applicationId: answers.applicationId,
        ),
      );
      await _renderer.render(projectRoot: staging.directory, answers: answers);
      await _verifier.verify(staging.directory);
      await staging.publish();
      return destination;
    } finally {
      await staging.dispose();
    }
  }
}

final class ProjectGenerationException implements Exception {
  const ProjectGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}
