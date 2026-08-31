import 'model_field_spec.dart';

/// Immutable source metadata for one parsed model class.
final class ModelClassSpec {
  ModelClassSpec({
    required this.name,
    required Iterable<ModelFieldSpec> fields,
    required Iterable<String> annotations,
    required this.documentation,
    required Iterable<String> preservedMembers,
    required this.hasCopyWith,
    required this.sourceOffset,
  })  : _fields = List.unmodifiable(fields),
        _annotations = List.unmodifiable(annotations),
        _preservedMembers = List.unmodifiable(preservedMembers) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  final String name;
  final List<ModelFieldSpec> _fields;
  final List<String> _annotations;
  final String? documentation;
  final List<String> _preservedMembers;
  final bool hasCopyWith;
  final int sourceOffset;

  List<ModelFieldSpec> get fields => _fields;
  List<String> get annotations => _annotations;
  List<String> get preservedMembers => _preservedMembers;
}
