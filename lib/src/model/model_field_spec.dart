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

/// Immutable source metadata for one declared model field.
final class ModelFieldSpec {
  const ModelFieldSpec({
    required this.name,
    required this.typeSource,
    required this.jsonKey,
    required this.kind,
    required this.isNullable,
    required this.nestedType,
    required this.sourceOffset,
  })  : assert(name != ''),
        assert(typeSource != ''),
        assert(nestedType == null || nestedType != ''),
        assert(
          (kind != ModelFieldKind.nestedModel &&
                  kind != ModelFieldKind.list &&
                  kind != ModelFieldKind.enumeration) ||
              (nestedType != null && nestedType != ''),
        );

  final String name;
  final String typeSource;
  final String jsonKey;
  final ModelFieldKind kind;
  final bool isNullable;
  final String? nestedType;
  final int sourceOffset;
}
