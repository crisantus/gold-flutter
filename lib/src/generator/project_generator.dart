import 'dart:io';

import '../config/project_answers.dart';

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

final class ProjectGenerationException implements Exception {
  const ProjectGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}
