import 'model_class_spec.dart';

/// Immutable source metadata for a complete Dart model file.
final class ModelFileSpec {
  ModelFileSpec({
    required Iterable<String> imports,
    required this.rootClassName,
    required Iterable<ModelClassSpec> classes,
    required Iterable<String> preservedTopLevelDeclarations,
  })  : _imports = List.unmodifiable(imports),
        _classes = List.unmodifiable(classes),
        _preservedTopLevelDeclarations =
            List.unmodifiable(preservedTopLevelDeclarations) {
    if (rootClassName.isEmpty) {
      throw ArgumentError.value(
          rootClassName, 'rootClassName', 'must not be empty');
    }
  }

  final List<String> _imports;
  final String rootClassName;
  final List<ModelClassSpec> _classes;
  final List<String> _preservedTopLevelDeclarations;

  List<String> get imports => _imports;
  List<ModelClassSpec> get classes => _classes;
  List<String> get preservedTopLevelDeclarations =>
      _preservedTopLevelDeclarations;
}
