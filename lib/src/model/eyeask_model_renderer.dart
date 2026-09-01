import 'model_class_spec.dart';
import 'model_field_spec.dart';
import 'model_file_spec.dart';
import 'model_top_level_function_spec.dart';

/// Renders parsed model metadata using the approved EyeAsk source style.
final class EyeAskModelRenderer {
  const EyeAskModelRenderer();

  String render(
    ModelFileSpec spec, {
    required bool addCopyWith,
  }) {
    final generatesRootDecoder = spec.rootClassName != null &&
        !_declaresHelper(
          spec,
          ModelTopLevelFunctionRole.rootDecoder,
        );
    final generatesRootEncoder = spec.rootClassName != null &&
        !_declaresHelper(
          spec,
          ModelTopLevelFunctionRole.rootEncoder,
        );
    final buffer = StringBuffer()
      ..writeln('// ignore_for_file: prefer_single_quotes')
      ..writeln();

    final hasDartConvert = spec.imports.any(
      (import) =>
          import.contains("'dart:convert'") ||
          import.contains('"dart:convert"'),
    );
    if ((generatesRootDecoder || generatesRootEncoder) && !hasDartConvert) {
      buffer.writeln("import 'dart:convert';");
    }
    for (final import in spec.imports) {
      buffer.writeln(import);
    }
    buffer.writeln();

    final declarations = spec.preservedTopLevelDeclarations;
    if (spec.rootClassName case final rootClassName?) {
      final rootPrefix = _lowercaseFirst(rootClassName);
      final fromJsonHelper = '${rootPrefix}FromJson';
      final toJsonHelper = '${rootPrefix}ToJson';
      if (generatesRootDecoder) {
        buffer
          ..writeln('$rootClassName $fromJsonHelper(String str) =>')
          ..writeln(
            '    $rootClassName.fromJson('
            'json.decode(str) as Map<String, dynamic>);',
          )
          ..writeln();
      }
      if (generatesRootEncoder) {
        buffer
          ..writeln(
            'String $toJsonHelper($rootClassName data) => '
            'json.encode(data.toJson());',
          )
          ..writeln();
      }
    }

    for (final declaration in declarations) {
      buffer
        ..writeln(declaration)
        ..writeln();
    }

    final classNames = spec.classes.map((model) => model.name).toSet();
    final enumNames = spec.classes
        .expand((model) => model.fields)
        .where((field) => field.kind == ModelFieldKind.enumeration)
        .map((field) => field.nestedType!)
        .toSet();
    for (var index = 0; index < spec.classes.length; index++) {
      _writeClass(
        buffer,
        spec.classes[index],
        classNames: classNames,
        enumNames: enumNames,
        addCopyWith: addCopyWith,
      );
      if (index != spec.classes.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }
}

void _writeClass(
  StringBuffer buffer,
  ModelClassSpec model, {
  required Set<String> classNames,
  required Set<String> enumNames,
  required bool addCopyWith,
}) {
  if (model.documentation case final documentation?) {
    buffer.writeln(documentation);
  }
  for (final annotation in model.annotations) {
    buffer.writeln(annotation);
  }
  buffer.writeln('class ${model.name} {');

  for (final field in model.fields) {
    buffer.writeln('  final ${field.typeSource} ${field.name};');
  }

  buffer.writeln();
  _writeConstructor(buffer, model);
  for (final constructor in model.preservedConstructors) {
    buffer
      ..writeln()
      ..writeln('  $constructor');
  }
  buffer.writeln();
  if (model.preservedFromJson case final preservedFromJson?) {
    buffer.writeln('  $preservedFromJson');
  } else {
    _writeFromJson(buffer, model);
  }
  buffer.writeln();
  _writeEmpty(buffer, model);
  buffer.writeln();
  for (final helper in model.preservedHelperMembers) {
    buffer
      ..writeln('  $helper')
      ..writeln();
  }
  _writeToJson(
    buffer,
    model,
    classNames: classNames,
    enumNames: enumNames,
  );

  final copyWithMembers = model.preservedMembers
      .where((member) => _isCopyWithMember(member, model.name));
  final customMembers = model.preservedMembers
      .where((member) => !_isCopyWithMember(member, model.name));
  if (model.fields.isNotEmpty && addCopyWith && !model.hasCopyWith) {
    buffer.writeln();
    _writeCopyWith(buffer, model);
  }
  for (final member in copyWithMembers.followedBy(customMembers)) {
    buffer
      ..writeln()
      ..writeln('  $member');
  }

  buffer.writeln('}');
}

void _writeConstructor(StringBuffer buffer, ModelClassSpec model) {
  if (model.fields.isEmpty) {
    buffer.writeln('  ${model.name}();');
    return;
  }
  if (model.fields.length == 1) {
    final field = model.fields.single;
    buffer.writeln(
      '  ${model.name}({required this.${field.name}});',
    );
    return;
  }

  buffer.writeln('  ${model.name}({');
  for (final field in model.fields) {
    buffer.writeln('    required this.${field.name},');
  }
  buffer.writeln('  });');
}

void _writeFromJson(StringBuffer buffer, ModelClassSpec model) {
  if (model.fields.isEmpty) {
    buffer.writeln(
      '  factory ${model.name}.fromJson(Map<String, dynamic>? json) => '
      '${model.name}();',
    );
    return;
  }
  buffer.writeln(
    '  factory ${model.name}.fromJson(Map<String, dynamic>? json) => '
    '${model.name}(',
  );
  for (final field in model.fields) {
    _writeFromJsonField(buffer, field);
  }
  buffer.writeln('      );');
}

void _writeFromJsonField(StringBuffer buffer, ModelFieldSpec field) {
  final name = field.name;
  final key = _dartDoubleQuotedString(field.jsonKey);
  switch (field.kind) {
    case ModelFieldKind.string:
      buffer.writeln('        $name: (json?[$key] ?? "").toString(),');
    case ModelFieldKind.integer:
      final fallback = field.isNullable ? '' : ' ?? 0';
      buffer.writeln(
        '        $name: int.tryParse('
        '(json?[$key] ?? "").toString())$fallback,',
      );
    case ModelFieldKind.doubleValue:
      final fallback = field.isNullable ? '' : ' ?? 0.0';
      buffer.writeln(
        '        $name: double.tryParse('
        '(json?[$key] ?? "").toString())$fallback,',
      );
    case ModelFieldKind.numeric:
      final fallback = field.isNullable ? '' : ' ?? 0';
      buffer.writeln(
        '        $name: num.tryParse('
        '(json?[$key] ?? "").toString())$fallback,',
      );
    case ModelFieldKind.boolean:
      buffer
        ..writeln('        $name: json?[$key] is bool')
        ..writeln('            ? json![$key] as bool')
        ..writeln(
          '            : (json?[$key] ?? "").toString() == "true",',
        );
    case ModelFieldKind.dateTime:
      if (field.isNullable) {
        buffer
          ..writeln('        $name: DateTime.tryParse(')
          ..writeln('          (json?[$key] ?? "").toString(),')
          ..writeln('        ),');
      } else {
        buffer
          ..writeln('        $name: DateTime.tryParse(')
          ..writeln('              (json?[$key] ?? "").toString(),')
          ..writeln('            ) ??')
          ..writeln('            DateTime.now(),');
      }
    case ModelFieldKind.nestedModel:
      if (field.isNullable) {
        buffer
          ..writeln('        $name: json?[$key] is Map<String, dynamic>')
          ..writeln(
            '            ? ${field.nestedType}.fromJson(json?[$key])',
          )
          ..writeln('            : null,');
      } else {
        buffer.writeln(
          '        $name: ${field.nestedType}.fromJson(json?[$key]),',
        );
      }
    case ModelFieldKind.list:
      _writeListFromJson(buffer, field);
    case ModelFieldKind.enumeration:
      buffer.writeln(
        '        $name: _${field.name}FromJson(json?[$key]),',
      );
  }
}

void _writeListFromJson(StringBuffer buffer, ModelFieldSpec field) {
  final key = _dartDoubleQuotedString(field.jsonKey);
  final elementType = field.nestedType!;
  buffer.writeln(
    '        ${field.name}: '
    '(json?[$key] is List ? json![$key] as List : [])',
  );
  final conversion = switch (elementType) {
    'String' => 'item.toString()',
    'int' => 'int.tryParse(item.toString()) ?? 0',
    'double' => 'double.tryParse(item.toString()) ?? 0.0',
    'num' => 'num.tryParse(item.toString()) ?? 0',
    'bool' => 'item is bool ? item : item.toString() == "true"',
    'DateTime' => 'DateTime.tryParse(item.toString()) ?? DateTime.now()',
    _ => '$elementType.fromJson(item)',
  };
  buffer
    ..writeln('            .map((item) => $conversion)')
    ..writeln('            .toList(),');
}

void _writeEmpty(StringBuffer buffer, ModelClassSpec model) {
  if (model.fields.isEmpty) {
    buffer.writeln('  factory ${model.name}.empty() => ${model.name}();');
    return;
  }
  buffer.writeln('  factory ${model.name}.empty() => ${model.name}(');
  for (final field in model.fields) {
    buffer.writeln('        ${field.name}: ${_emptyValue(field)},');
  }
  buffer.writeln('      );');
}

String _emptyValue(ModelFieldSpec field) {
  if (field.isNullable) {
    return 'null';
  }
  return switch (field.kind) {
    ModelFieldKind.string => '""',
    ModelFieldKind.integer => '0',
    ModelFieldKind.doubleValue => '0.0',
    ModelFieldKind.numeric => '0',
    ModelFieldKind.boolean => 'false',
    ModelFieldKind.dateTime => 'DateTime.now()',
    ModelFieldKind.nestedModel => '${field.nestedType}.empty()',
    ModelFieldKind.list => '[]',
    ModelFieldKind.enumeration => '_${field.name}FromJson(null)',
  };
}

void _writeToJson(
  StringBuffer buffer,
  ModelClassSpec model, {
  required Set<String> classNames,
  required Set<String> enumNames,
}) {
  if (model.fields.isEmpty) {
    buffer.writeln('  Map<String, dynamic> toJson() => {};');
    return;
  }
  buffer.writeln('  Map<String, dynamic> toJson() => {');
  for (final field in model.fields) {
    final value = _toJsonValue(
      field,
      classNames: classNames,
      enumNames: enumNames,
    );
    final key = _dartDoubleQuotedString(field.jsonKey);
    buffer.writeln('        $key: $value,');
  }
  buffer.writeln('      };');
}

String _toJsonValue(
  ModelFieldSpec field, {
  required Set<String> classNames,
  required Set<String> enumNames,
}) {
  switch (field.kind) {
    case ModelFieldKind.dateTime:
      return field.isNullable
          ? '${field.name}?.toIso8601String()'
          : '${field.name}.toIso8601String()';
    case ModelFieldKind.nestedModel:
      return field.isNullable
          ? '${field.name}?.toJson()'
          : '${field.name}.toJson()';
    case ModelFieldKind.enumeration:
      return field.isNullable ? '${field.name}?.name' : '${field.name}.name';
    case ModelFieldKind.list:
      return _listToJsonValue(
        field,
        classNames: classNames,
        enumNames: enumNames,
      );
    case ModelFieldKind.string:
    case ModelFieldKind.integer:
    case ModelFieldKind.doubleValue:
    case ModelFieldKind.numeric:
    case ModelFieldKind.boolean:
      return field.name;
  }
}

String _listToJsonValue(
  ModelFieldSpec field, {
  required Set<String> classNames,
  required Set<String> enumNames,
}) {
  final elementType = field.nestedType!;
  final access = field.isNullable ? '${field.name}?' : field.name;
  if (classNames.contains(elementType)) {
    return '$access.map((item) => item.toJson()).toList()';
  }
  if (elementType == 'DateTime') {
    return '$access.map((item) => item.toIso8601String()).toList()';
  }
  if (enumNames.contains(elementType)) {
    return '$access.map((item) => item.name).toList()';
  }
  return field.name;
}

void _writeCopyWith(StringBuffer buffer, ModelClassSpec model) {
  buffer.writeln('  ${model.name} copyWith({');
  for (final field in model.fields) {
    buffer.writeln('    ${_nullableType(field.typeSource)} ${field.name},');
  }
  buffer.writeln('  }) {');
  buffer.writeln('    return ${model.name}(');
  for (final field in model.fields) {
    buffer.writeln(
      '      ${field.name}: ${field.name} ?? this.${field.name},',
    );
  }
  buffer
    ..writeln('    );')
    ..writeln('  }');
}

String _nullableType(String typeSource) {
  return typeSource.endsWith('?') ? typeSource : '$typeSource?';
}

bool _isCopyWithMember(String member, String className) {
  return member.contains('$className copyWith(');
}

bool _declaresHelper(
  ModelFileSpec spec,
  ModelTopLevelFunctionRole role,
) =>
    spec.topLevelFunctions.any((function) => function.role == role);

String _lowercaseFirst(String value) {
  return '${value[0].toLowerCase()}${value.substring(1)}';
}

String _dartDoubleQuotedString(String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x08:
        buffer.write(r'\b');
      case 0x09:
        buffer.write(r'\t');
      case 0x0a:
        buffer.write(r'\n');
      case 0x0c:
        buffer.write(r'\f');
      case 0x0d:
        buffer.write(r'\r');
      case 0x22:
        buffer.write(r'\"');
      case 0x24:
        buffer.write(r'\$');
      case 0x5c:
        buffer.write(r'\\');
      default:
        if (rune < 0x20 ||
            (rune >= 0x7f && rune <= 0x9f) ||
            rune == 0x2028 ||
            rune == 0x2029) {
          buffer
            ..write(r'\u{')
            ..write(rune.toRadixString(16))
            ..write('}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  return '${buffer.toString()}"';
}
