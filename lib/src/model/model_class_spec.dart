import 'model_field_spec.dart';

/// Immutable source metadata for one parsed model class.
final class ModelClassSpec {
  ModelClassSpec({
    required this.name,
    required Iterable<ModelFieldSpec> fields,
    required Iterable<String> annotations,
    required this.documentation,
    Iterable<String> preservedConstructors = const [],
    required Iterable<String> preservedMembers,
    Iterable<String> preservedHelperMembers = const [],
    this.preservedFromJson,
    this.supportsDirectObjectFromJson = true,
    required this.hasCopyWith,
    required this.sourceOffset,
  })  : _fields = List.unmodifiable(fields),
        _annotations = List.unmodifiable(annotations),
        _preservedConstructors = List.unmodifiable(preservedConstructors),
        _preservedMembers = List.unmodifiable(preservedMembers),
        _preservedHelperMembers = List.unmodifiable(preservedHelperMembers) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  final String name;
  final List<ModelFieldSpec> _fields;
  final List<String> _annotations;
  final String? documentation;
  final List<String> _preservedConstructors;
  final List<String> _preservedMembers;
  final List<String> _preservedHelperMembers;
  final String? preservedFromJson;
  final bool supportsDirectObjectFromJson;
  final bool hasCopyWith;
  final int sourceOffset;

  List<ModelFieldSpec> get fields => _fields;
  List<String> get annotations => _annotations;
  List<String> get preservedConstructors => _preservedConstructors;
  List<String> get preservedMembers => _preservedMembers;
  List<String> get preservedHelperMembers => _preservedHelperMembers;
}
