import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'model_class_spec.dart';
import 'model_field_spec.dart';
import 'model_file_spec.dart';

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
    final topLevelFunctionNames = unit.declarations
        .whereType<FunctionDeclaration>()
        .map((declaration) => declaration.name.lexeme)
        .toSet();
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

    final imports = unit.directives
        .whereType<ImportDirective>()
        .map((directive) => _sourceSlice(source, directive));
    final preservedTopLevelDeclarations = unit.declarations
        .where((declaration) => declaration is! ClassDeclaration)
        .map((declaration) => _sourceSlice(source, declaration));

    return ModelParseResult(
      spec: ModelFileSpec(
        imports: imports,
        rootClassName: classSpecs.first.name,
        classes: classSpecs,
        preservedTopLevelDeclarations: preservedTopLevelDeclarations,
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
    final fields = <_ParsedField>[];
    final fieldNames = <String>{};
    final preservedMembers = <String>[];
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
        if (_isSupportedStructuralMethod(member, className)) {
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

    if (fields.isEmpty && diagnostics.isNotEmpty) {
      return null;
    }

    final fromJsonConstructors = declaration.members
        .whereType<ConstructorDeclaration>()
        .where((constructor) => constructor.name?.lexeme == 'fromJson')
        .toList();
    if (fields.isNotEmpty && fromJsonConstructors.length != 1) {
      diagnostics.add(
        '$className must declare exactly one fromJson constructor in $path.',
      );
      return null;
    }

    final fieldSpecs = <ModelFieldSpec>[];
    if (fields.isNotEmpty) {
      final arguments = _returnedClassArguments(
        fromJsonConstructors.single.body,
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
        final keys = _terminalJsonKeys(expression);
        if (keys.length != 1) {
          diagnostics.add(
            'Unable to uniquely discover a JSON key for '
            '$className.${field.name} in $path.',
          );
          continue;
        }
        if (field.shape.kind == ModelFieldKind.list &&
            !_isSupportedListElement(field.shape.nestedType!, classNames)) {
          diagnostics.add(
            'Unsupported list element ${field.shape.nestedType} for '
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
            jsonKey: keys.single,
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
      preservedMembers: preservedMembers,
      hasCopyWith: hasCopyWith,
      sourceOffset: declaration.offset,
    );
  }
}

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

Set<String> _terminalJsonKeys(Expression expression) {
  final visitor = _JsonKeyVisitor();
  expression.accept(visitor);
  return visitor.keys;
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

final class _JsonKeyVisitor extends RecursiveAstVisitor<void> {
  final Set<String> keys = {};

  @override
  void visitIndexExpression(IndexExpression node) {
    final index = node.index;
    if (!_isIntermediateIndexReceiver(node) &&
        _jsonTargetDepth(node.realTarget) != null &&
        index is SimpleStringLiteral) {
      keys.add(index.value);
    }
    super.visitIndexExpression(node);
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

int? _jsonTargetDepth(Expression expression) {
  if (expression is SimpleIdentifier) {
    return expression.name == 'json' ? 0 : null;
  }
  if (expression is ParenthesizedExpression) {
    return _jsonTargetDepth(expression.expression);
  }
  if (expression is PostfixExpression) {
    return _jsonTargetDepth(expression.operand);
  }
  if (expression is IndexExpression) {
    final depth = _jsonTargetDepth(expression.realTarget);
    return depth == null ? null : depth + 1;
  }
  return null;
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

bool _isSupportedStructuralMethod(
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
    case 'toJson':
      return !method.isStatic &&
          parameters.parameters.isEmpty &&
          _typeSourceIs(method.returnType, 'Map<String, dynamic>');
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
