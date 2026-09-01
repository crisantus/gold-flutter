final class ProjectDocumentation {
  ProjectDocumentation.normalized({
    required this.projectName,
    required Iterable<String> dependencies,
    required Iterable<String> assets,
    required Iterable<String> layers,
    required Iterable<RouteDocumentation> routes,
    required Iterable<ModelDocumentation> models,
    required Iterable<String> unknownFacts,
    required this.generatedAtVersion,
  })  : dependencies = _sorted(dependencies),
        assets = _sorted(assets),
        layers = _sorted(layers),
        routes = List.unmodifiable(routes),
        models = List.unmodifiable(models),
        unknownFacts = _sorted(unknownFacts);

  final String projectName;
  final List<String> dependencies;
  final List<String> assets;
  final List<String> layers;
  final List<RouteDocumentation> routes;
  final List<ModelDocumentation> models;
  final List<String> unknownFacts;
  final String generatedAtVersion;

  static List<String> _sorted(Iterable<String> values) {
    final result = values.toSet().toList()..sort();
    return List.unmodifiable(result);
  }
}

final class RouteDocumentation {
  const RouteDocumentation({
    required this.name,
    required this.path,
    required this.isInitial,
  });

  final String name;
  final String? path;
  final bool isInitial;
}

final class ModelDocumentation {
  const ModelDocumentation({required this.name, required this.fields});

  final String name;
  final List<ModelFieldDocumentation> fields;
}

final class ModelFieldDocumentation {
  const ModelFieldDocumentation({required this.name, required this.type});

  final String name;
  final String type;
}
