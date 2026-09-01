/// The supported shapes of a parsed model field.
enum ModelFieldKind {
  string,
  integer,
  doubleValue,
  numeric,
  boolean,
  dateTime,
  nestedModel,
  list,
  enumeration,
}

/// How a model field's JSON key was established.
enum ModelJsonKeyOrigin {
  discovered,
  derived,
}

/// Immutable source metadata for one declared model field.
final class ModelFieldSpec {
  ModelFieldSpec({
    required this.name,
    required this.typeSource,
    required this.jsonKey,
    this.jsonKeyOrigin = ModelJsonKeyOrigin.discovered,
    required this.kind,
    required this.isNullable,
    required this.nestedType,
    required this.sourceOffset,
  }) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (typeSource.isEmpty) {
      throw ArgumentError.value(typeSource, 'typeSource', 'must not be empty');
    }
    if (nestedType != null && nestedType!.isEmpty) {
      throw ArgumentError.value(nestedType, 'nestedType', 'must not be empty');
    }
    if (_requiresNestedType(kind) && nestedType == null) {
      throw ArgumentError.value(
        nestedType,
        'nestedType',
        'is required for ${kind.name} fields',
      );
    }
  }

  final String name;
  final String typeSource;
  final String jsonKey;
  final ModelJsonKeyOrigin jsonKeyOrigin;
  final ModelFieldKind kind;
  final bool isNullable;
  final String? nestedType;
  final int sourceOffset;

  bool get isJsonKeyDerived => jsonKeyOrigin == ModelJsonKeyOrigin.derived;

  static bool _requiresNestedType(ModelFieldKind kind) {
    return kind == ModelFieldKind.nestedModel ||
        kind == ModelFieldKind.list ||
        kind == ModelFieldKind.enumeration;
  }
}
