import 'model_class_spec.dart';
import 'model_top_level_function_spec.dart';

/// Immutable source metadata for a complete Dart model file.
final class ModelFileSpec {
  ModelFileSpec({
    required Iterable<String> imports,
    required this.rootClassName,
    required Iterable<ModelClassSpec> classes,
    required Iterable<String> preservedTopLevelDeclarations,
    Iterable<ModelTopLevelFunctionSpec> topLevelFunctions = const [],
  })  : _imports = List.unmodifiable(imports),
        _classes = List.unmodifiable(classes),
        _preservedTopLevelDeclarations =
            List.unmodifiable(preservedTopLevelDeclarations),
        _topLevelFunctions = List.unmodifiable(topLevelFunctions) {
    if (rootClassName != null && rootClassName!.isEmpty) {
      throw ArgumentError.value(
          rootClassName, 'rootClassName', 'must not be empty');
    }
  }

  final List<String> _imports;
  final String? rootClassName;
  final List<ModelClassSpec> _classes;
  final List<String> _preservedTopLevelDeclarations;
  final List<ModelTopLevelFunctionSpec> _topLevelFunctions;

  List<String> get imports => _imports;
  List<ModelClassSpec> get classes => _classes;
  List<String> get preservedTopLevelDeclarations =>
      _preservedTopLevelDeclarations;
  List<ModelTopLevelFunctionSpec> get topLevelFunctions => _topLevelFunctions;
}
