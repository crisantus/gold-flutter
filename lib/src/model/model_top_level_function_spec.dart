/// The structural role of a parsed top-level model helper.
enum ModelTopLevelFunctionRole {
  other,
  rootDecoder,
  rootEncoder,
}

/// Immutable AST-derived metadata for one preserved top-level function.
final class ModelTopLevelFunctionSpec {
  const ModelTopLevelFunctionSpec({
    required this.name,
    required this.source,
    required this.role,
    required this.sourceOffset,
  });

  final String name;
  final String source;
  final ModelTopLevelFunctionRole role;
  final int sourceOffset;
}
