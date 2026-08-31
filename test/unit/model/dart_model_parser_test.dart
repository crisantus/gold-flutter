import 'dart:io';

import 'package:gold_flutter/src/model/dart_model_parser.dart';
import 'package:gold_flutter/src/model/model_field_spec.dart';
import 'package:test/test.dart';

void main() {
  const parser = DartModelParser();

  test('extracts ordered EyeAsk fields and their source JSON keys', () {
    final source =
        File('test/fixtures/models/eyeask_input.dart').readAsStringSync();

    final result =
        parser.parse(source, 'test/fixtures/models/eyeask_input.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.diagnostics, isEmpty);
    final spec = result.spec!;
    expect(spec.imports, ["import 'dart:convert';"]);
    expect(spec.rootClassName, 'ReportModel');
    expect(spec.classes.map((model) => model.name), ['ReportModel']);

    final report = spec.classes.single;
    expect(report.fields.map((field) => field.name), [
      'id',
      'page',
      'ready',
      'createdAt',
      'deletedAt',
      'user',
      'items',
    ]);
    expect(report.fields.map((field) => field.jsonKey), [
      'id',
      'current_page',
      'ready',
      'created_at',
      'deleted_at',
      'user',
      'items',
    ]);
    expect(report.fields.map((field) => field.typeSource), [
      'String',
      'int',
      'bool',
      'DateTime',
      'DateTime?',
      'UserModel',
      'List<ItemModel>',
    ]);
    expect(report.fields.map((field) => field.kind), [
      ModelFieldKind.string,
      ModelFieldKind.integer,
      ModelFieldKind.boolean,
      ModelFieldKind.dateTime,
      ModelFieldKind.dateTime,
      ModelFieldKind.nestedModel,
      ModelFieldKind.list,
    ]);
    expect(report.fields[4].isNullable, isTrue);
    expect(report.fields[5].nestedType, 'UserModel');
    expect(report.fields[6].nestedType, 'ItemModel');
    expect(report.preservedMembers, [r"String get label => '$id:$page';"]);
  });

  test('refuses the complete file when one field shape is unsupported', () {
    final source =
        File('test/fixtures/models/unsupported_input.dart').readAsStringSync();

    final result =
        parser.parse(source, 'test/fixtures/models/unsupported_input.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.grouped'));
  });

  test('refuses syntax errors without throwing a parser exception', () {
    const source = 'class BrokenModel { final String id }';

    final result = parser.parse(source, 'broken_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics, isNotEmpty);
  });

  test('refuses duplicate class names for the complete source file', () {
    const source = '''
class UserModel {}
class UserModel {}
''';

    final result = parser.parse(source, 'duplicate.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('UserModel'));
  });

  test('accepts enum fields and preserves their converter source', () {
    const source = '''
enum Status { active, inactive }

class ReportModel {
  final Status status;

  ReportModel({required this.status});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        status: _statusFromJson(json?["status"]),
      );
}

Status _statusFromJson(dynamic value) {
  return Status.values.firstWhere(
    (status) => status.name == value?.toString(),
    orElse: () => Status.inactive,
  );
}
''';

    final result = parser.parse(source, 'status_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(
      result.spec!.classes.single.fields.single.kind,
      ModelFieldKind.enumeration,
    );
    expect(result.spec!.classes.single.fields.single.nestedType, 'Status');
    expect(result.spec!.preservedTopLevelDeclarations, [
      'enum Status { active, inactive }',
      '''Status _statusFromJson(dynamic value) {
  return Status.values.firstWhere(
    (status) => status.name == value?.toString(),
    orElse: () => Status.inactive,
  );
}''',
    ]);
  });

  test('refuses enum fields without a preserved named converter', () {
    const source = '''
enum Status { active, inactive }

class ReportModel {
  final Status status;

  ReportModel({required this.status});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        status: Status.values.byName((json?["status"] ?? "").toString()),
      );
}
''';

    final result = parser.parse(source, 'inline_status_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.status'));
  });

  test('preserves ordered classes and custom source metadata exactly', () {
    const source = '''
import 'package:meta/meta.dart';

const marker = 1;

/// A user from the API.
@immutable
class UserModel {
  final String id;

  UserModel({required this.id});

  factory UserModel.fromJson(Map<String, dynamic>? json) => UserModel(
        id: (json?["user_id"] ?? "").toString(),
      );

  String get displayId => id;
}

class ReportModel {
  final UserModel user;

  ReportModel({required this.user});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        user: UserModel.fromJson(json?["user"]),
      );
}
''';

    final result = parser.parse(source, 'multiple_models.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    final spec = result.spec!;
    expect(spec.classes.map((model) => model.name), [
      'UserModel',
      'ReportModel',
    ]);
    expect(spec.rootClassName, 'UserModel');
    expect(spec.imports, ["import 'package:meta/meta.dart';"]);
    expect(spec.preservedTopLevelDeclarations, ['const marker = 1;']);
    expect(spec.classes.first.documentation, '/// A user from the API.');
    expect(spec.classes.first.annotations, ['@immutable']);
    expect(spec.classes.first.fields.single.jsonKey, 'user_id');
    expect(
      spec.classes.first.preservedMembers,
      ['String get displayId => id;'],
    );
  });

  test('refuses ambiguous JSON-key mappings for a field', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? json?["legacy_id"] ?? "").toString(),
      );
}
''';

    final result = parser.parse(source, 'ambiguous_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.id'));
  });

  test('maps fields returned through a private named constructor', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel._({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel._(
        id: (json?["id"] ?? "").toString(),
      );
}
''';

    final result = parser.parse(source, 'named_constructor_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.spec!.classes.single.fields.single.jsonKey, 'id');
  });
}
