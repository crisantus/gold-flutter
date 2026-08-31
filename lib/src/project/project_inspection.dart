import 'dart:io';

final class ProjectInspection {
  ProjectInspection({
    required this.root,
    required this.projectName,
    required Set<String> dependencies,
    required List<String> assets,
    required this.hasTests,
    required this.hasGit,
    required this.isDirty,
  })  : dependencies = Set.unmodifiable(dependencies),
        assets = List.unmodifiable(assets);

  final Directory root;
  final String projectName;
  final Set<String> dependencies;
  final List<String> assets;
  final bool hasTests;
  final bool hasGit;
  final bool isDirty;
}
