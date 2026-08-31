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
    expect(spec.classes.map((model) => model.name), [
      'ReportModel',
      'UserModel',
      'ItemModel',
    ]);

    final report = spec.classes.first;
    expect(report.fields.map((field) => field.name), [
      'id',
      'page',
      'price',
      'total',
      'ready',
      'createdAt',
      'deletedAt',
      'user',
      'items',
    ]);
    expect(report.fields.map((field) => field.jsonKey), [
      'id',
      'current_page',
      'price',
      'total',
      'ready',
      'created_at',
      'deleted_at',
      'user',
      'items',
    ]);
    expect(report.fields.map((field) => field.typeSource), [
      'String',
      'int',
      'double',
      'num',
      'bool',
      'DateTime',
      'DateTime?',
      'UserModel',
      'List<ItemModel>',
    ]);
    expect(report.fields.map((field) => field.kind), [
      ModelFieldKind.string,
      ModelFieldKind.integer,
      ModelFieldKind.doubleValue,
      ModelFieldKind.numeric,
      ModelFieldKind.boolean,
      ModelFieldKind.dateTime,
      ModelFieldKind.dateTime,
      ModelFieldKind.nestedModel,
      ModelFieldKind.list,
    ]);
    expect(report.fields[6].isNullable, isTrue);
    expect(report.fields[7].nestedType, 'UserModel');
    expect(report.fields[8].nestedType, 'ItemModel');
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

  test('preserves uncertain same-name members and copyWith exactly', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  bool get empty => id.isEmpty;

  set empty(bool value) {}

  Map<String, dynamic> toJson(int version) => {
        "id": id,
        "version": version,
      };

  List<ReportModel> fromJsonList(int version) => [this];

  ReportModel copyWith({String? id}) {
    return ReportModel(id: id ?? this.id);
  }
}
''';

    final result = parser.parse(source, 'custom_members_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    final model = result.spec!.classes.single;
    expect(model.hasCopyWith, isTrue);
    expect(model.preservedMembers, [
      'bool get empty => id.isEmpty;',
      'set empty(bool value) {}',
      '''Map<String, dynamic> toJson(int version) => {
        "id": id,
        "version": version,
      };''',
      'List<ReportModel> fromJsonList(int version) => [this];',
      '''ReportModel copyWith({String? id}) {
    return ReportModel(id: id ?? this.id);
  }''',
    ]);
  });

  test('omits only supported structural method signatures', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  Map<String, dynamic> toJson() => {"id": id};

  static List<ReportModel> fromJsonList(dynamic json) => [];
}
''';

    final result = parser.parse(source, 'structural_members_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.spec!.classes.single.preservedMembers, isEmpty);
  });

  test('ignores incidental construction and refuses a cached return', () {
    const source = '''
final cachedReport = ReportModel(id: "cached");

class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) {
    ReportModel(id: (json?["incidental"] ?? "").toString());
    return cachedReport;
  }
}
''';

    final result = parser.parse(source, 'cached_return_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.fromJson'));
  });

  test('refuses multiple returned constructions as ambiguous', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return ReportModel(id: "missing");
    }
    return ReportModel(id: (json["id"] ?? "").toString());
  }
}
''';

    final result = parser.parse(source, 'multiple_returns_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.fromJson'));
  });

  test('refuses a wrapped unsupported return expression', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => choose(
        ReportModel(id: (json?["id"] ?? "").toString()),
      );
}

ReportModel choose(ReportModel value) => value;
''';

    final result = parser.parse(source, 'wrapped_return_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.fromJson'));
  });

  test('refuses a call to an undeclared named constructor', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      ReportModel.unknown(id: (json?["id"] ?? "").toString());
}
''';

    final result = parser.parse(source, 'unknown_constructor_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.fromJson'));
  });

  test('refuses a prefixed external construction with the local class name',
      () {
    const source = '''
import "other.dart" as other;

class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      new other.ReportModel(id: (json?["id"] ?? "").toString());
}
''';

    final result = parser.parse(source, 'prefixed_constructor_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.fromJson'));
  });

  test('uses the actual block return and records literal source offsets', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel._({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) {
    final fallback = ReportModel._(id: "fallback");
    fallback.toString();
    return ReportModel._(
      id: (json?["id"] ?? "").toString(),
    );
  }
}
''';

    final result = parser.parse(source, 'block_return_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    final model = result.spec!.classes.single;
    expect(model.sourceOffset, 0);
    expect(model.fields.single.sourceOffset, 35);
    expect(model.fields.single.jsonKey, 'id');
  });

  test('refuses duplicate final field names for the complete file', () {
    const source = '''
class ReportModel {
  final String id;
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );
}
''';

    final result = parser.parse(source, 'duplicate_field_model.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.id'));
  });

  test('discovers the leaf key through a parenthesized index receiver', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: ((json?["payload"])["id"] ?? "").toString(),
      );
}
''';

    final result = parser.parse(source, 'parenthesized_key_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.spec!.classes.single.fields.single.jsonKey, 'id');
  });

  test('discovers the leaf key through a null-checked index receiver', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic> json) => ReportModel(
        id: (json["payload"]!["id"] ?? "").toString(),
      );
}
''';

    final result = parser.parse(source, 'null_checked_key_model.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.spec!.classes.single.fields.single.jsonKey, 'id');
  });
}
