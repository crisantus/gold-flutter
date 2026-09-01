import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'model_class_spec.dart';
import 'model_field_spec.dart';
import 'model_file_spec.dart';
import 'model_top_level_function_spec.dart';

/// The safe result of parsing one complete Dart model source file.
final class ModelParseResult {
  ModelParseResult({
    required this.spec,
    required Iterable<String> diagnostics,
  }) : _diagnostics = List.unmodifiable(diagnostics);

  final ModelFileSpec? spec;
  final List<String> _diagnostics;

  List<String> get diagnostics => _diagnostics;

  bool get isSafe => spec != null && diagnostics.isEmpty;
}

/// Extracts supported model metadata from Dart analyzer syntax trees.
final class DartModelParser {
  const DartModelParser();

  ModelParseResult parse(String source, String path) {
    try {
      return _parse(source, path);
    } on Object catch (error) {
      return ModelParseResult(
        spec: null,
        diagnostics: ['Unable to safely parse $path: $error'],
      );
    }
  }

  ModelParseResult _parse(String source, String path) {
    final parsed = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    final syntaxErrors = parsed.errors
        .where(
          (error) => error.errorCode.errorSeverity == ErrorSeverity.ERROR,
        )
        .map((error) => '$path:${error.offset}: ${error.message}')
        .toList(growable: false);
    if (syntaxErrors.isNotEmpty) {
      return ModelParseResult(spec: null, diagnostics: syntaxErrors);
    }

    final unit = parsed.unit;
    final classes = unit.declarations.whereType<ClassDeclaration>().toList();
    if (classes.isEmpty) {
      return ModelParseResult(
        spec: null,
        diagnostics: ['$path does not declare a model class.'],
      );
    }

    final diagnostics = <String>[];
    final seenClassNames = <String>{};
    for (final declaration in classes) {
      final name = declaration.name.lexeme;
      if (!seenClassNames.add(name)) {
        diagnostics.add('Duplicate model class $name in $path.');
      }
    }
    if (diagnostics.isNotEmpty) {
      return ModelParseResult(spec: null, diagnostics: diagnostics);
    }

    final unsupportedDirectives =
        unit.directives.where((directive) => directive is! ImportDirective);
    for (final directive in unsupportedDirectives) {
      diagnostics.add(
        'Unsupported directive in $path: ${_sourceSlice(source, directive)}',
      );
    }

    final enumNames = unit.declarations
        .whereType<EnumDeclaration>()
        .map((declaration) => declaration.name.lexeme)
        .toSet();
    final classNames =
        classes.map((declaration) => declaration.name.lexeme).toSet();
    final topLevelFunctions =
        unit.declarations.whereType<FunctionDeclaration>().toList();
    final topLevelFunctionNames =
        topLevelFunctions.map((declaration) => declaration.name.lexeme).toSet();
    final classSpecs = <ModelClassSpec>[];
    for (final declaration in classes) {
      final classSpec = _parseClass(
        declaration,
        source,
        path,
        classNames,
        enumNames,
        topLevelFunctionNames,
        diagnostics,
      );
      if (classSpec != null) {
        classSpecs.add(classSpec);
      }
    }

    if (diagnostics.isNotEmpty || classSpecs.length != classes.length) {
      return ModelParseResult(spec: null, diagnostics: diagnostics);
    }

    _diagnoseNonNullableNestedCycles(classSpecs, path, diagnostics);

    final publicClassNames = classSpecs
        .where((model) => !_isPrivateIdentifier(model.name))
        .map((model) => model.name)
        .toList(growable: false);
    final rootClassName =
        publicClassNames.isEmpty ? null : publicClassNames.first;
    final topLevelFunctionSpecs = _parseTopLevelFunctions(
      topLevelFunctions,
      unit.declarations,
      source,
      path,
      rootClassName,
      diagnostics,
    );

    if (diagnostics.isNotEmpty) {
      return ModelParseResult(spec: null, diagnostics: diagnostics);
    }

    final imports = unit.directives
        .whereType<ImportDirective>()
        .map((directive) => _sourceSlice(source, directive));
    final preservedTopLevelDeclarations = unit.declarations
        .where((declaration) => declaration is! ClassDeclaration)
        .map((declaration) => _sourceSlice(source, declaration));

    return ModelParseResult(
      spec: ModelFileSpec(
        imports: imports,
        rootClassName: rootClassName,
        classes: classSpecs,
        preservedTopLevelDeclarations: preservedTopLevelDeclarations,
        topLevelFunctions: topLevelFunctionSpecs,
      ),
      diagnostics: const [],
    );
  }

  ModelClassSpec? _parseClass(
    ClassDeclaration declaration,
    String source,
    String path,
    Set<String> classNames,
    Set<String> enumNames,
    Set<String> topLevelFunctionNames,
    List<String> diagnostics,
  ) {
    final className = declaration.name.lexeme;
    final unsupportedHeader = _unsupportedClassHeader(declaration);
    if (unsupportedHeader != null) {
      diagnostics.add(
        'Unsupported $unsupportedHeader class header for $className in '
        '$path:${declaration.offset}.',
      );
      return null;
    }
    final diagnosticStart = diagnostics.length;
    final fields = <_ParsedField>[];
    final fieldNames = <String>{};
    final preservedConstructors = <String>[];
    final preservedMembers = <String>[];
    final preservedHelperMembers = <String>[];
    var hasCopyWith = false;
    final converterNames = {
      ...topLevelFunctionNames,
      ...declaration.members
          .whereType<MethodDeclaration>()
          .map((member) => member.name.lexeme),
    };

    for (final member in declaration.members) {
      if (member is FieldDeclaration) {
        if (member.isStatic || member.fields.isConst) {
          final collisions = member.fields.variables
              .where(
                (variable) =>
                    _generatedStructureNames.contains(variable.name.lexeme),
              )
              .toList();
          for (final variable in collisions) {
            diagnostics.add(
              'Unsupported structural member '
              '$className.${variable.name.lexeme} in '
              '$path:${variable.offset}.',
            );
          }
          if (collisions.isNotEmpty) {
            continue;
          }
          preservedMembers.add(_sourceSlice(source, member));
          continue;
        }
        if (!member.fields.isFinal) {
          diagnostics.add(
            'Unsupported non-final model field in $className at '
            '$path:${member.offset}.',
          );
          continue;
        }

        final type = member.fields.type;
        for (final variable in member.fields.variables) {
          final fieldName = variable.name.lexeme;
          if (!fieldNames.add(fieldName)) {
            diagnostics.add(
              'Duplicate model field $className.$fieldName in $path.',
            );
            continue;
          }
          if (variable.initializer != null) {
            diagnostics.add(
              'Unsupported initialized model field '
              '$className.$fieldName in $path.',
            );
            continue;
          }
          if (type is! NamedType) {
            diagnostics.add(
              'Unsupported field type for $className.$fieldName in $path.',
            );
            continue;
          }
          final shape = _fieldShape(type, enumNames);
          if (shape == null) {
            diagnostics.add(
              'Unsupported field type ${type.toSource()} for '
              '$className.$fieldName in $path.',
            );
            continue;
          }
          fields.add(
            _ParsedField(
              name: fieldName,
              typeSource: type.toSource(),
              shape: shape,
              sourceOffset: variable.offset,
            ),
          );
        }
        continue;
      }

      if (member is ConstructorDeclaration) {
        final name = member.name?.lexeme;
        if (name != null &&
            name != 'fromJson' &&
            !_generatedStructureNames.contains(name)) {
          preservedConstructors.add(_sourceSlice(source, member));
        }
        continue;
      }

      if (member is MethodDeclaration) {
        final name = member.name.lexeme;
        if (member.isStatic && _generatedStructureNames.contains(name)) {
          diagnostics.add(
            'Unsupported structural member $className.$name in '
            '$path:${member.offset}.',
          );
          continue;
        }
        if (name == 'copyWith') {
          if (_isSupportedCopyWith(member, className)) {
            hasCopyWith = true;
            preservedMembers.add(_sourceSlice(source, member));
          } else {
            diagnostics.add(
              'Unsupported structural member $className.$name in '
              '$path:${member.offset}.',
            );
          }
          continue;
        }
        if (_isSupportedToJsonMethod(member)) {
          continue;
        }
        if (_isSupportedListHelper(member, className)) {
          preservedHelperMembers.add(_sourceSlice(source, member));
          continue;
        }
        if (_collidesWithGeneratedStructure(member)) {
          diagnostics.add(
            'Unsupported structural member $className.$name in '
            '$path:${member.offset}.',
          );
          continue;
        }
      }

      preservedMembers.add(_sourceSlice(source, member));
    }

    if (fields.isEmpty && diagnostics.length != diagnosticStart) {
      return null;
    }

    final fromJsonConstructors = declaration.members
        .whereType<ConstructorDeclaration>()
        .where((constructor) => constructor.name?.lexeme == 'fromJson')
        .toList();
    if ((fields.isNotEmpty && fromJsonConstructors.length != 1) ||
        fromJsonConstructors.length > 1) {
      diagnostics.add(
        '$className must declare exactly one fromJson constructor in $path.',
      );
      return null;
    }

    final fromJson =
        fromJsonConstructors.isEmpty ? null : fromJsonConstructors.first;
    if (fromJson != null && !_hasSupportedFromJsonSignature(fromJson)) {
      diagnostics.add(
        'Unsupported $className.fromJson parameter contract in '
        '$path:${fromJson.offset}; expected exactly one required positional '
        'Map<String, dynamic> or Map<String, dynamic>? parameter named json.',
      );
      return null;
    }

    final fieldSpecs = <ModelFieldSpec>[];
    var preserveFromJson = false;
    var supportsDirectObjectFromJson = true;
    if (fields.isNotEmpty) {
      final aliases = _JsonAliasAnalysis.fromBody(fromJson!.body);
      final arguments = _returnedClassArguments(
        fromJson.body,
        className,
        declaration.members
            .whereType<ConstructorDeclaration>()
            .map((constructor) => constructor.name?.lexeme)
            .whereType<String>()
            .where((name) => name != 'fromJson')
            .toSet(),
      );
      if (arguments == null) {
        diagnostics.add(
          'Unable to find the $className.fromJson return expression in $path.',
        );
        return null;
      }

      final namedArguments = <String, List<NamedExpression>>{};
      for (final argument in arguments.arguments) {
        if (argument is NamedExpression) {
          namedArguments
              .putIfAbsent(argument.name.label.name, () => [])
              .add(argument);
        }
      }

      for (final field in fields) {
        final matchingArguments = namedArguments[field.name] ?? const [];
        if (matchingArguments.length != 1) {
          diagnostics.add(
            'Unable to uniquely map $className.${field.name} in $path.',
          );
          continue;
        }
        final expression = matchingArguments.single.expression;
        final access = _jsonAccess(expression, aliases);
        if (access.unresolvedAliases.isNotEmpty) {
          diagnostics.add(
            'Unable to safely resolve JSON alias '
            '${access.unresolvedAliases.join(', ')} for '
            '$className.${field.name} in $path.',
          );
          continue;
        }
        final keys = access.paths.map((path) => path.last).toSet();
        if (keys.length > 1) {
          diagnostics.add(
            'Unable to uniquely discover a JSON key for '
            '$className.${field.name} in $path.',
          );
          continue;
        }
        final keyOrigin = keys.isEmpty
            ? ModelJsonKeyOrigin.derived
            : ModelJsonKeyOrigin.discovered;
        final jsonKey =
            keys.isEmpty ? _snakeCaseJsonKey(field.name) : keys.single;
        preserveFromJson = preserveFromJson ||
            access.usesAlias ||
            access.paths.any((path) => path.length > 1);
        if (access.paths.any((path) => path.length > 1)) {
          supportsDirectObjectFromJson = false;
        }
        if (field.shape.kind == ModelFieldKind.list &&
            !_isSupportedListElement(field.shape.nestedType!, classNames)) {
          diagnostics.add(
            'Unsupported list element ${field.shape.nestedType} for '
            '$className.${field.name} in $path.',
          );
          continue;
        }
        if (field.shape.kind == ModelFieldKind.nestedModel &&
            !classNames.contains(field.shape.nestedType)) {
          diagnostics.add(
            'Unsupported nested model ${field.shape.nestedType} for '
            '$className.${field.name} in $path.',
          );
          continue;
        }
        if (field.shape.kind == ModelFieldKind.enumeration) {
          final converterName = '_${field.name}FromJson';
          if (!converterNames.contains(converterName) ||
              !_callsNamed(expression, converterName)) {
            diagnostics.add(
              'Missing supported $converterName converter for '
              '$className.${field.name} in $path.',
            );
            continue;
          }
        }
        fieldSpecs.add(
          ModelFieldSpec(
            name: field.name,
            typeSource: field.typeSource,
            jsonKey: jsonKey,
            jsonKeyOrigin: keyOrigin,
            kind: field.shape.kind,
            isNullable: field.shape.isNullable,
            nestedType: field.shape.nestedType,
            sourceOffset: field.sourceOffset,
          ),
        );
      }
    }

    if (fieldSpecs.length != fields.length) {
      return null;
    }

    final documentation = declaration.documentationComment;
    return ModelClassSpec(
      name: className,
      fields: fieldSpecs,
      annotations: declaration.metadata
          .map((annotation) => _sourceSlice(source, annotation)),
      documentation:
          documentation == null ? null : _sourceSlice(source, documentation),
      preservedConstructors: preservedConstructors,
      preservedMembers: preservedMembers,
      preservedHelperMembers: preservedHelperMembers,
      preservedFromJson:
          preserveFromJson ? _sourceSlice(source, fromJson!) : null,
      supportsDirectObjectFromJson: supportsDirectObjectFromJson,
      hasCopyWith: hasCopyWith,
      sourceOffset: declaration.offset,
    );
  }
}

String? _unsupportedClassHeader(ClassDeclaration declaration) {
  if (declaration.abstractKeyword != null) {
    return 'abstract';
  }
  if (declaration.classKeyword.previous?.lexeme == 'augment') {
    return 'augment';
  }
  if (declaration.baseKeyword != null) {
    return 'base';
  }
  if (declaration.finalKeyword != null) {
    return 'final';
  }
  if (declaration.interfaceKeyword != null) {
    return 'interface';
  }
  if (declaration.sealedKeyword != null) {
    return 'sealed';
  }
  if (declaration.mixinKeyword != null) {
    return 'mixin class';
  }
  if (declaration.typeParameters != null) {
    return 'type parameters';
  }
  if (declaration.extendsClause != null) {
    return 'extends';
  }
  if (declaration.withClause != null) {
    return 'with';
  }
  if (declaration.implementsClause != null) {
    return 'implements';
  }
  if (declaration.nativeClause != null) {
    return 'native';
  }
  return null;
}

List<ModelTopLevelFunctionSpec> _parseTopLevelFunctions(
  List<FunctionDeclaration> functions,
  Iterable<CompilationUnitMember> declarations,
  String source,
  String path,
  String? rootClassName,
  List<String> diagnostics,
) {
  final specs = <ModelTopLevelFunctionSpec>[];
  if (rootClassName == null) {
    return [
      for (final function in functions)
        ModelTopLevelFunctionSpec(
          name: function.name.lexeme,
          source: _sourceSlice(source, function),
          role: ModelTopLevelFunctionRole.other,
          sourceOffset: function.offset,
        ),
    ];
  }

  final prefix = _lowercaseFirst(rootClassName);
  final decoderName = '${prefix}FromJson';
  final encoderName = '${prefix}ToJson';
  final structuralNames = {decoderName, encoderName};
  for (final declaration
      in declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final variable in declaration.variables.variables) {
      if (structuralNames.contains(variable.name.lexeme)) {
        diagnostics.add(
          'Unsupported root helper ${variable.name.lexeme} in '
          '$path:${variable.offset}; expected a top-level function.',
        );
      }
    }
  }

  for (final name in structuralNames) {
    final matches = functions.where((function) => function.name.lexeme == name);
    if (matches.length > 1) {
      diagnostics.add('Duplicate root helper $name in $path.');
    }
  }

  for (final function in functions) {
    final name = function.name.lexeme;
    var role = ModelTopLevelFunctionRole.other;
    if (name == decoderName) {
      if (!_isSupportedRootDecoder(function, rootClassName)) {
        diagnostics.add(
          'Unsupported root decoder $name in $path:${function.offset}.',
        );
      } else {
        role = ModelTopLevelFunctionRole.rootDecoder;
      }
    } else if (name == encoderName) {
      if (!_isSupportedRootEncoder(function, rootClassName)) {
        diagnostics.add(
          'Unsupported root encoder $name in $path:${function.offset}.',
        );
      } else {
        role = ModelTopLevelFunctionRole.rootEncoder;
      }
    }
    specs.add(
      ModelTopLevelFunctionSpec(
        name: name,
        source: _sourceSlice(source, function),
        role: role,
        sourceOffset: function.offset,
      ),
    );
  }
  return specs;
}

bool _isSupportedRootDecoder(
  FunctionDeclaration function,
  String rootClassName,
) {
  final parameters = function.functionExpression.parameters;
  return !function.isGetter &&
      !function.isSetter &&
      function.externalKeyword == null &&
      function.functionExpression.typeParameters == null &&
      parameters != null &&
      _hasSingleRequiredParameterOfType(parameters, 'String') &&
      (_typeSourceIs(function.returnType, rootClassName) ||
          _typeSourceIs(function.returnType, 'List<$rootClassName>'));
}

bool _isSupportedRootEncoder(
  FunctionDeclaration function,
  String rootClassName,
) {
  final parameters = function.functionExpression.parameters;
  return !function.isGetter &&
      !function.isSetter &&
      function.externalKeyword == null &&
      function.functionExpression.typeParameters == null &&
      parameters != null &&
      (_hasSingleRequiredParameterOfType(parameters, rootClassName) ||
          _hasSingleRequiredParameterOfType(
            parameters,
            'List<$rootClassName>',
          )) &&
      _typeSourceIs(function.returnType, 'String');
}

void _diagnoseNonNullableNestedCycles(
  List<ModelClassSpec> classes,
  String path,
  List<String> diagnostics,
) {
  final edges = {
    for (final model in classes)
      model.name: model.fields
          .where(
            (field) =>
                field.kind == ModelFieldKind.nestedModel && !field.isNullable,
          )
          .map((field) => field.nestedType!)
          .toList(growable: false),
  };
  final state = <String, int>{};
  final stack = <String>[];
  final reported = <String>{};

  void visit(String name) {
    state[name] = 1;
    stack.add(name);
    for (final target in edges[name] ?? const []) {
      if (state[target] == 1) {
        final start = stack.indexOf(target);
        final cycle = [...stack.sublist(start), target];
        final signature = cycle.join(' -> ');
        if (reported.add(signature)) {
          diagnostics.add(
            'Unsupported nonnullable nested-model cycle in $path: '
            '$signature.',
          );
        }
      } else if (state[target] != 2) {
        visit(target);
      }
    }
    stack.removeLast();
    state[name] = 2;
  }

  for (final name in edges.keys) {
    if (state[name] == null) {
      visit(name);
    }
  }
}

String _snakeCaseJsonKey(String name) {
  return name
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .toLowerCase();
}

bool _isPrivateIdentifier(String name) => name.startsWith('_');

String _lowercaseFirst(String value) =>
    '${value.substring(0, 1).toLowerCase()}${value.substring(1)}';

_FieldShape? _fieldShape(NamedType type, Set<String> enumNames) {
  final name = type.name2.lexeme;
  final isNullable = type.question != null;
  final hasPrefix = type.importPrefix != null;
  final typeArguments =
      type.typeArguments?.arguments ?? const <TypeAnnotation>[];

  if (!hasPrefix && typeArguments.isEmpty) {
    final primitiveKind = switch (name) {
      'String' => ModelFieldKind.string,
      'int' => ModelFieldKind.integer,
      'double' => ModelFieldKind.doubleValue,
      'num' => ModelFieldKind.numeric,
      'bool' => ModelFieldKind.boolean,
      'DateTime' => ModelFieldKind.dateTime,
      _ => null,
    };
    if (primitiveKind != null) {
      return _FieldShape(
        kind: primitiveKind,
        isNullable: isNullable,
        nestedType: null,
      );
    }
    if (_unsupportedSimpleTypes.contains(name)) {
      return null;
    }
    final kind = enumNames.contains(name)
        ? ModelFieldKind.enumeration
        : ModelFieldKind.nestedModel;
    return _FieldShape(
      kind: kind,
      isNullable: isNullable,
      nestedType: _withoutTrailingQuestion(type.toSource()),
    );
  }

  if (!hasPrefix && name == 'List' && typeArguments.length == 1) {
    final elementType = typeArguments.single;
    if (elementType is! NamedType || elementType.question != null) {
      return null;
    }
    if (elementType.typeArguments != null ||
        _unsupportedListElementTypes.contains(elementType.name2.lexeme)) {
      return null;
    }
    return _FieldShape(
      kind: ModelFieldKind.list,
      isNullable: isNullable,
      nestedType: elementType.toSource(),
    );
  }

  if (hasPrefix && typeArguments.isEmpty) {
    return _FieldShape(
      kind: ModelFieldKind.nestedModel,
      isNullable: isNullable,
      nestedType: _withoutTrailingQuestion(type.toSource()),
    );
  }

  return null;
}

const _unsupportedSimpleTypes = {
  'dynamic',
  'Object',
  'Never',
  'void',
  'Map',
  'Set',
  'Iterable',
  'Function',
};

const _unsupportedListElementTypes = {
  'dynamic',
  'Object',
  'Never',
  'void',
  'Map',
  'Set',
  'Iterable',
  'Function',
  'List',
};

String _withoutTrailingQuestion(String source) {
  return source.endsWith('?') ? source.substring(0, source.length - 1) : source;
}

ArgumentList? _returnedClassArguments(
  FunctionBody body,
  String className,
  Set<String> namedConstructorNames,
) {
  if (body is ExpressionFunctionBody) {
    return _classConstructionArguments(
      body.expression,
      className,
      namedConstructorNames,
    );
  }
  if (body is! BlockFunctionBody) {
    return null;
  }

  final visitor = _ReturnStatementVisitor();
  body.block.accept(visitor);
  if (visitor.returns.length != 1) {
    return null;
  }
  final expression = visitor.returns.single.expression;
  if (expression == null) {
    return null;
  }
  return _classConstructionArguments(
    expression,
    className,
    namedConstructorNames,
  );
}

_JsonAccess _jsonAccess(
  Expression expression,
  _JsonAliasAnalysis aliases,
) {
  final visitor = _JsonAccessVisitor(aliases);
  expression.accept(visitor);
  return _JsonAccess(
    paths: visitor.paths,
    usesAlias: visitor.usesAlias,
    unresolvedAliases: visitor.unresolvedAliases,
  );
}

bool _callsNamed(Expression expression, String name) {
  final visitor = _NamedCallVisitor(name);
  expression.accept(visitor);
  return visitor.found;
}

String _sourceSlice(String source, AstNode node) {
  return source.substring(node.offset, node.end);
}

final class _ParsedField {
  const _ParsedField({
    required this.name,
    required this.typeSource,
    required this.shape,
    required this.sourceOffset,
  });

  final String name;
  final String typeSource;
  final _FieldShape shape;
  final int sourceOffset;
}

final class _FieldShape {
  const _FieldShape({
    required this.kind,
    required this.isNullable,
    required this.nestedType,
  });

  final ModelFieldKind kind;
  final bool isNullable;
  final String? nestedType;
}

final class _JsonAccess {
  const _JsonAccess({
    required this.paths,
    required this.usesAlias,
    required this.unresolvedAliases,
  });

  final List<List<String>> paths;
  final bool usesAlias;
  final Set<String> unresolvedAliases;
}

final class _JsonAccessVisitor extends RecursiveAstVisitor<void> {
  _JsonAccessVisitor(this.aliases);

  final _JsonAliasAnalysis aliases;
  final List<List<String>> paths = [];
  final Set<String> unresolvedAliases = {};
  var usesAlias = false;

  @override
  void visitIndexExpression(IndexExpression node) {
    final index = node.index;
    if (!_isIntermediateIndexReceiver(node) && index is SimpleStringLiteral) {
      final localTargets = _referencedIdentifiers(
        node.realTarget,
        aliases.localNames,
      );
      final targetPaths = _jsonTargetPaths(
        node.realTarget,
        aliases.resolved,
      );
      for (final path in targetPaths) {
        _addPath([...path, index.value]);
      }
      if (localTargets.isNotEmpty) {
        usesAlias = true;
      }
      if (targetPaths.isEmpty && localTargets.isNotEmpty) {
        unresolvedAliases.addAll(localTargets);
      }
      unresolvedAliases.addAll(
        localTargets.where((name) => aliases.unsafe.contains(name)),
      );
      return;
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (!aliases.localNames.contains(name)) {
      super.visitSimpleIdentifier(node);
      return;
    }
    usesAlias = true;
    final aliasPaths = aliases.resolved[name];
    if (aliasPaths == null || aliases.unsafe.contains(name)) {
      unresolvedAliases.add(name);
      return;
    }
    for (final path in aliasPaths) {
      if (path.isEmpty || path.last == _opaqueJsonAliasSegment) {
        unresolvedAliases.add(name);
      } else {
        _addPath(path);
      }
    }
  }

  void _addPath(List<String> path) {
    if (!paths.any((candidate) => _samePath(candidate, path))) {
      paths.add(path);
    }
  }
}

final class _ReturnStatementVisitor extends RecursiveAstVisitor<void> {
  final List<ReturnStatement> returns = [];

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitReturnStatement(ReturnStatement node) {
    returns.add(node);
  }
}

final class _NamedCallVisitor extends RecursiveAstVisitor<void> {
  _NamedCallVisitor(this.name);

  final String name;
  var found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == name) {
      found = true;
    }
    super.visitMethodInvocation(node);
  }
}

List<List<String>> _jsonTargetPaths(
  Expression expression,
  Map<String, List<List<String>>> aliases,
) {
  if (expression is SimpleIdentifier) {
    if (expression.name == 'json') {
      return const [<String>[]];
    }
    return aliases[expression.name] ?? const [];
  }
  if (expression is ParenthesizedExpression) {
    return _jsonTargetPaths(expression.expression, aliases);
  }
  if (expression is PostfixExpression) {
    return _jsonTargetPaths(expression.operand, aliases);
  }
  if (expression is AsExpression) {
    return _jsonTargetPaths(expression.expression, aliases);
  }
  if (expression is IndexExpression) {
    final index = expression.index;
    if (index is! SimpleStringLiteral) {
      return const [];
    }
    return [
      for (final path in _jsonTargetPaths(expression.realTarget, aliases))
        [...path, index.value],
    ];
  }
  if (expression is BinaryExpression && expression.operator.lexeme == '??') {
    return _uniquePaths([
      ..._jsonTargetPaths(expression.leftOperand, aliases),
      ..._jsonTargetPaths(expression.rightOperand, aliases),
    ]);
  }
  if (expression is ConditionalExpression) {
    return _uniquePaths([
      ..._jsonTargetPaths(expression.thenExpression, aliases),
      ..._jsonTargetPaths(expression.elseExpression, aliases),
    ]);
  }
  if (expression is MethodInvocation &&
      expression.methodName.name == 'from' &&
      expression.argumentList.arguments.length == 1) {
    return _jsonTargetPaths(
      expression.argumentList.arguments.single,
      aliases,
    );
  }
  return const [];
}

final class _JsonAliasAnalysis {
  _JsonAliasAnalysis._({
    required this.localNames,
    required Map<String, List<VariableDeclaration>> declarations,
    required Set<String> writtenNames,
  })  : _declarations = declarations,
        _writtenNames = writtenNames;

  factory _JsonAliasAnalysis.fromBody(FunctionBody body) {
    if (body is! BlockFunctionBody) {
      return _JsonAliasAnalysis._(
        localNames: const {},
        declarations: const {},
        writtenNames: const {},
      );
    }
    final declarations = _LocalDeclarationVisitor();
    body.block.accept(declarations);
    final localNames = declarations.variables.keys.toSet();
    final writes = _LocalWriteVisitor(localNames);
    body.block.accept(writes);
    final analysis = _JsonAliasAnalysis._(
      localNames: localNames,
      declarations: declarations.variables,
      writtenNames: writes.names,
    );
    for (final name in localNames) {
      analysis._resolve(name, <String>{});
    }
    return analysis;
  }

  final Set<String> localNames;
  final Map<String, List<VariableDeclaration>> _declarations;
  final Set<String> _writtenNames;
  final Map<String, List<List<String>>> resolved = {};
  final Set<String> unsafe = {};

  void _resolve(String name, Set<String> visiting) {
    if (resolved.containsKey(name) || unsafe.contains(name)) {
      return;
    }
    final declarations = _declarations[name] ?? const [];
    if (declarations.length != 1 || _writtenNames.contains(name)) {
      unsafe.add(name);
      return;
    }
    final initializer = declarations.single.initializer;
    if (initializer == null || !visiting.add(name)) {
      unsafe.add(name);
      return;
    }

    final dependencies = _referencedIdentifiers(initializer, localNames);
    for (final dependency in dependencies) {
      _resolve(dependency, visiting);
    }
    visiting.remove(name);
    if (dependencies.any(unsafe.contains)) {
      unsafe.add(name);
      return;
    }

    var paths = _jsonTargetPaths(initializer, resolved);
    if (paths.isEmpty &&
        (_referencesAnyIdentifier(initializer, const {'json'}) ||
            dependencies.any(resolved.containsKey))) {
      paths = const [
        [_opaqueJsonAliasSegment],
      ];
    }
    if (paths.isEmpty) {
      unsafe.add(name);
    } else {
      resolved[name] = paths;
    }
  }
}

final class _LocalDeclarationVisitor extends RecursiveAstVisitor<void> {
  final Map<String, List<VariableDeclaration>> variables = {};

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    variables.putIfAbsent(node.name.lexeme, () => []).add(node);
    super.visitVariableDeclaration(node);
  }
}

final class _LocalWriteVisitor extends RecursiveAstVisitor<void> {
  _LocalWriteVisitor(this.localNames);

  final Set<String> localNames;
  final Set<String> names = {};

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    names.addAll(_referencedIdentifiers(node.leftHandSide, localNames));
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.lexeme == '++' || node.operator.lexeme == '--') {
      names.addAll(_referencedIdentifiers(node.operand, localNames));
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.lexeme == '++' || node.operator.lexeme == '--') {
      names.addAll(_referencedIdentifiers(node.operand, localNames));
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (_mutatingMethodNames.contains(node.methodName.name) && target != null) {
      names.addAll(_referencedIdentifiers(target, localNames));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitCascadeExpression(CascadeExpression node) {
    final mutates = node.cascadeSections.whereType<MethodInvocation>().any(
          (section) => _mutatingMethodNames.contains(section.methodName.name),
        );
    if (mutates) {
      names.addAll(_referencedIdentifiers(node.target, localNames));
    }
    super.visitCascadeExpression(node);
  }
}

const _mutatingMethodNames = {
  'add',
  'addAll',
  'clear',
  'fillRange',
  'insert',
  'insertAll',
  'putIfAbsent',
  'remove',
  'removeAt',
  'removeLast',
  'removeRange',
  'removeWhere',
  'replaceRange',
  'retainWhere',
  'setAll',
  'setRange',
  'shuffle',
  'sort',
  'update',
  'updateAll',
};

const _opaqueJsonAliasSegment = '\u0000gold_flutter_opaque_json_alias';

List<List<String>> _uniquePaths(Iterable<List<String>> paths) {
  final unique = <List<String>>[];
  for (final path in paths) {
    if (!unique.any((candidate) => _samePath(candidate, path))) {
      unique.add(path);
    }
  }
  return unique;
}

bool _samePath(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _referencesAnyIdentifier(
  AstNode node,
  Iterable<String> identifiers,
) {
  final visitor = _IdentifierVisitor(identifiers.toSet());
  node.accept(visitor);
  return visitor.found;
}

Set<String> _referencedIdentifiers(
  AstNode node,
  Set<String> identifiers,
) {
  final visitor = _IdentifierSetVisitor(identifiers);
  node.accept(visitor);
  return visitor.found;
}

final class _IdentifierVisitor extends RecursiveAstVisitor<void> {
  _IdentifierVisitor(this.identifiers);

  final Set<String> identifiers;
  var found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (identifiers.contains(node.name)) {
      found = true;
    }
    super.visitSimpleIdentifier(node);
  }
}

final class _IdentifierSetVisitor extends RecursiveAstVisitor<void> {
  _IdentifierSetVisitor(this.identifiers);

  final Set<String> identifiers;
  final Set<String> found = {};

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (identifiers.contains(node.name)) {
      found.add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }
}

ArgumentList? _classConstructionArguments(
  Expression expression,
  String className,
  Set<String> namedConstructorNames,
) {
  final unwrapped = _unwrapParentheses(expression);
  if (unwrapped is InstanceCreationExpression) {
    final constructor = unwrapped.constructorName;
    if (constructor.type.importPrefix != null ||
        constructor.type.name2.lexeme != className) {
      return null;
    }
    final constructorName = constructor.name?.name;
    if (constructorName != null &&
        !namedConstructorNames.contains(constructorName)) {
      return null;
    }
    return unwrapped.argumentList;
  }
  if (unwrapped is! MethodInvocation) {
    return null;
  }

  final target = unwrapped.target;
  final invokesDefaultConstructor =
      target == null && unwrapped.methodName.name == className;
  final invokesNamedConstructor = target is SimpleIdentifier &&
      target.name == className &&
      namedConstructorNames.contains(unwrapped.methodName.name);
  return invokesDefaultConstructor || invokesNamedConstructor
      ? unwrapped.argumentList
      : null;
}

Expression _unwrapParentheses(Expression expression) {
  var current = expression;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
}

bool _isIntermediateIndexReceiver(IndexExpression node) {
  AstNode receiver = node;
  AstNode? parent = receiver.parent;
  while (true) {
    if (parent is ParenthesizedExpression && parent.expression == receiver) {
      receiver = parent;
      parent = receiver.parent;
      continue;
    }
    if (parent is PostfixExpression &&
        parent.operand == receiver &&
        parent.operator.lexeme == '!') {
      receiver = parent;
      parent = receiver.parent;
      continue;
    }
    break;
  }
  return parent is IndexExpression && parent.target == receiver;
}

bool _isSupportedToJsonMethod(MethodDeclaration method) {
  if (method.isGetter ||
      method.isSetter ||
      method.isOperator ||
      method.isAbstract ||
      method.externalKeyword != null ||
      method.typeParameters != null) {
    return false;
  }
  final parameters = method.parameters;
  if (parameters == null) {
    return false;
  }

  return method.name.lexeme == 'toJson' &&
      !method.isStatic &&
      parameters.parameters.isEmpty &&
      _typeSourceIs(method.returnType, 'Map<String, dynamic>');
}

bool _isSupportedListHelper(
  MethodDeclaration method,
  String className,
) {
  if (method.isGetter ||
      method.isSetter ||
      method.isOperator ||
      method.isAbstract ||
      method.externalKeyword != null ||
      method.typeParameters != null) {
    return false;
  }
  final parameters = method.parameters;
  if (parameters == null) {
    return false;
  }

  switch (method.name.lexeme) {
    case 'fromJsonList':
    case 'listFromJson':
      return method.isStatic &&
          _hasSingleRequiredParameterOfType(parameters, 'dynamic') &&
          _typeSourceIs(method.returnType, 'List<$className>');
    case 'toJsonList':
    case 'listToJson':
      return method.isStatic &&
          _hasSingleRequiredParameterOfType(
            parameters,
            'List<$className>',
          ) &&
          _typeSourceIs(
            method.returnType,
            'List<Map<String, dynamic>>',
          );
    default:
      return false;
  }
}

bool _hasSupportedFromJsonSignature(ConstructorDeclaration constructor) {
  if (constructor.factoryKeyword == null ||
      constructor.externalKeyword != null ||
      constructor.redirectedConstructor != null ||
      constructor.parameters.parameters.length != 1) {
    return false;
  }
  final parameter = constructor.parameters.parameters.single;
  if (!parameter.isRequiredPositional) {
    return false;
  }
  final normal =
      parameter is DefaultFormalParameter ? parameter.parameter : parameter;
  return normal is SimpleFormalParameter &&
      normal.name?.lexeme == 'json' &&
      (_typeSourceIs(normal.type, 'Map<String, dynamic>') ||
          _typeSourceIs(normal.type, 'Map<String, dynamic>?'));
}

bool _isSupportedCopyWith(MethodDeclaration method, String className) {
  if (method.isStatic ||
      method.isGetter ||
      method.isSetter ||
      method.isOperator ||
      method.isAbstract ||
      method.externalKeyword != null ||
      method.typeParameters != null ||
      !_typeSourceIs(method.returnType, className)) {
    return false;
  }
  final parameters = method.parameters;
  return parameters != null &&
      parameters.parameters.every((parameter) => parameter.isOptionalNamed);
}

bool _collidesWithGeneratedStructure(MethodDeclaration method) {
  switch (method.name.lexeme) {
    case 'fromJson':
    case 'toJson':
      return true;
    case 'empty':
      return !method.isGetter && !method.isSetter;
    default:
      return false;
  }
}

bool _hasSingleRequiredParameterOfType(
  FormalParameterList parameters,
  String typeSource,
) {
  if (parameters.parameters.length != 1) {
    return false;
  }
  final parameter = parameters.parameters.single;
  if (!parameter.isRequiredPositional) {
    return false;
  }
  final normal =
      parameter is DefaultFormalParameter ? parameter.parameter : parameter;
  return normal is SimpleFormalParameter &&
      _typeSourceIs(normal.type, typeSource);
}

bool _typeSourceIs(TypeAnnotation? type, String source) {
  return type is NamedType && type.toSource() == source;
}

const _generatedStructureNames = {
  'empty',
  'fromJson',
  'toJson',
  'copyWith',
};

bool _isSupportedListElement(String typeSource, Set<String> classNames) {
  return _supportedListScalarTypes.contains(typeSource) ||
      classNames.contains(typeSource);
}

const _supportedListScalarTypes = {
  'String',
  'int',
  'double',
  'num',
  'bool',
  'DateTime',
};
