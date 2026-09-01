import 'dart:io';

import 'package:gold_flutter/src/model/dart_model_parser.dart';
import 'package:gold_flutter/src/model/model_field_spec.dart';
import 'package:gold_flutter/src/model/model_top_level_function_spec.dart';
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

  test('refuses list fields whose local element type is an enum', () {
    const source = '''
enum Status { active, inactive }

class ReportModel {
  final List<Status> statuses;

  ReportModel({required this.statuses});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        statuses: (json?["statuses"] is List
                ? json!["statuses"] as List
                : [])
            .map(_statusFromJson)
            .toList(),
      );
}

Status _statusFromJson(dynamic value) {
  return Status.values.firstWhere(
    (status) => status.name == value?.toString(),
    orElse: () => Status.inactive,
  );
}
''';

    final result = parser.parse(source, 'local_enum_list.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.statuses'));
  });

  test('refuses list fields that invoke an enum-converter shape', () {
    const source = '''
class ReportModel {
  final List<RemoteStatus> statuses;

  ReportModel({required this.statuses});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        statuses: (json?["statuses"] is List
                ? json!["statuses"] as List
                : [])
            .map(_statusFromJson)
            .toList(),
      );
}

RemoteStatus _statusFromJson(dynamic value) => throw UnimplementedError();
''';

    final result = parser.parse(source, 'converter_enum_list.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.statuses'));
  });

  test('refuses an imported enum list using values.byName', () {
    const source = '''
import 'remote.dart' as remote;

class ReportModel {
  final List<remote.RemoteStatus> statuses;

  ReportModel({required this.statuses});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        statuses: (json?["statuses"] is List
                ? json!["statuses"] as List
                : [])
            .map(
              (item) => remote.RemoteStatus.values.byName(item.toString()),
            )
            .toList(),
      );
}
''';

    final result = parser.parse(source, 'imported_enum_list.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.statuses'));
  });

  test('refuses an imported model list without local structural proof', () {
    const source = '''
import 'remote.dart' as remote;

class ReportModel {
  final List<remote.RemoteModel> models;

  ReportModel({required this.models});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        models: (json?["models"] is List ? json!["models"] as List : [])
            .map((item) => remote.RemoteModel.fromJson(item))
            .toList(),
      );
}
''';

    final result = parser.parse(source, 'imported_model_list.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.models'));
  });

  test('accepts primitive, date, and model list element types', () {
    const source = '''
class ReportModel {
  final List<int> counts;
  final List<DateTime> dates;
  final List<ItemModel> items;

  ReportModel({
    required this.counts,
    required this.dates,
    required this.items,
  });

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        counts: (json?["counts"] is List ? json!["counts"] as List : [])
            .map((item) => int.tryParse(item.toString()) ?? 0)
            .toList(),
        dates: (json?["dates"] is List ? json!["dates"] as List : [])
            .map((item) => DateTime.parse(item.toString()))
            .toList(),
        items: (json?["items"] is List ? json!["items"] as List : [])
            .map((item) => ItemModel.fromJson(item))
            .toList(),
      );
}

class ItemModel {
  final String id;

  ItemModel({required this.id});

  factory ItemModel.fromJson(Map<String, dynamic>? json) => ItemModel(
        id: (json?["id"] ?? "").toString(),
      );
}
''';

    final result = parser.parse(source, 'supported_lists.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(
      result.spec!.classes.first.fields.map((field) => field.nestedType),
      ['int', 'DateTime', 'ItemModel'],
    );
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
    final model = result.spec!.classes.single;
    expect(model.fields.single.jsonKey, 'id');
    expect(model.preservedConstructors, [
      'ReportModel._({required this.id});',
    ]);
  });

  test('preserves safe empty accessors, custom helpers, and copyWith exactly',
      () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  bool get empty => id.isEmpty;

  set empty(bool value) {}

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
      'List<ReportModel> fromJsonList(int version) => [this];',
      '''ReportModel copyWith({String? id}) {
    return ReportModel(id: id ?? this.id);
  }''',
    ]);
  });

  test('refuses custom methods that collide with generated structure', () {
    const collidingMembers = {
      'toJson': '''Map<String, dynamic> toJson(int version) => {
    "id": id,
    "version": version,
  };''',
      'fromJson': 'String fromJson(int version) => id;',
      'empty': 'ReportModel empty(int version) => this;',
    };

    for (final entry in collidingMembers.entries) {
      final source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  ${entry.value}
}
''';

      final result = parser.parse(source, '${entry.key}_collision.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(
        result.diagnostics.join('\n'),
        contains('ReportModel.${entry.key}'),
        reason: entry.key,
      );
    }
  });

  const zeroFieldStaticCollisions = {
    'field': 'static const empty = 0;',
    'getter': 'static int get fromJson => 0;',
    'setter': 'static set toJson(int value) {}',
    'method': 'static EmptyModel copyWith() => EmptyModel();',
  };
  for (final entry in zeroFieldStaticCollisions.entries) {
    test('refuses a zero-field static ${entry.key} structural collision', () {
      final source = '''
class EmptyModel {
  ${entry.value}
}
''';

      final result = parser.parse(source, 'static_${entry.key}.dart');

      expect(result.isSafe, isFalse);
      expect(result.spec, isNull);
      expect(result.diagnostics.join('\n'), contains('EmptyModel.'));
    });
  }

  test('refuses nonempty static structural members including copyWith', () {
    const collidingMembers = {
      'empty': 'static ReportModel empty() => ReportModel(id: "");',
      'copyWith': 'static const copyWith = 1;',
    };

    for (final entry in collidingMembers.entries) {
      final source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  ${entry.value}
}
''';

      final result = parser.parse(source, 'static_${entry.key}.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(
        result.diagnostics.join('\n'),
        contains('ReportModel.${entry.key}'),
        reason: entry.key,
      );
    }
  });

  test('refuses an unsupported instance copyWith collision', () {
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  String copyWith({String? id}) => id ?? this.id;
}
''';

    final result = parser.parse(source, 'unsupported_copy_with.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('ReportModel.copyWith'));
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

  test('selects the first public class as the root without reordering classes',
      () {
    const source = '''
class _PayloadModel {
  final String id;

  _PayloadModel({required this.id});

  factory _PayloadModel.fromJson(Map<String, dynamic>? json) =>
      _PayloadModel(id: (json?["id"] ?? "").toString());
}

class ReportModel {
  final String title;

  ReportModel({required this.title});

  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      ReportModel(title: (json?["title"] ?? "").toString());
}
''';

    final result = parser.parse(source, 'first_public_root.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.spec!.rootClassName, 'ReportModel');
    expect(result.spec!.classes.map((model) => model.name), [
      '_PayloadModel',
      'ReportModel',
    ]);
  });

  test('allows a private-only file without assigning a public root', () {
    const source = '''
class _PayloadModel {
  final String id;

  _PayloadModel({required this.id});

  factory _PayloadModel.fromJson(Map<String, dynamic>? json) =>
      _PayloadModel(id: (json?["id"] ?? "").toString());
}
''';

    final result = parser.parse(source, 'private_only.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(result.spec!.rootClassName, isNull);
  });

  test('refuses class headers that the renderer cannot reproduce', () {
    const headers = {
      'abstract': 'abstract class ReportModel',
      'type parameters': 'class ReportModel<T>',
      'extends': 'class ReportModel extends BaseModel',
      'with': 'class ReportModel with Marker',
      'implements': 'class ReportModel implements Marker',
      'mixin class': 'mixin class ReportModel',
    };

    for (final entry in headers.entries) {
      final result = parser.parse('${entry.value} {}', 'header.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(result.diagnostics.join('\n'), contains('ReportModel'),
          reason: entry.key);
      expect(result.diagnostics.join('\n'), contains(entry.key),
          reason: entry.key);
    }
  });

  test('refuses scalar nested types without a local class contract', () {
    const sources = {
      'unknown': '''
class ReportModel {
  final RemoteModel remote;
  ReportModel({required this.remote});
  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      ReportModel(remote: RemoteModel.fromJson(json?["remote"]));
}
''',
      'prefixed': '''
import 'remote.dart' as remote;
class ReportModel {
  final remote.RemoteModel value;
  ReportModel({required this.value});
  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      ReportModel(value: remote.RemoteModel.fromJson(json?["value"]));
}
''',
    };

    for (final entry in sources.entries) {
      final result = parser.parse(entry.value, '${entry.key}.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(result.diagnostics.join('\n'), contains('ReportModel.'),
          reason: entry.key);
    }
  });

  test('validates the exact supported fromJson parameter contract', () {
    const parameters = {
      'wrong name': 'Map<String, dynamic>? payload',
      'wrong type': 'dynamic json',
      'extra parameter': 'Map<String, dynamic>? json, int version',
      'named parameter': '{Map<String, dynamic>? json}',
    };

    for (final entry in parameters.entries) {
      final source = '''
class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson(${entry.value}) => ReportModel(id: "");
}
''';
      final result = parser.parse(source, 'from_json_parameter.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(result.diagnostics.join('\n'), contains('ReportModel.fromJson'),
          reason: entry.key);
    }
  });

  test('accepts nullable and nonnullable supported fromJson maps', () {
    for (final type in const [
      'Map<String, dynamic>?',
      'Map<String, dynamic>',
    ]) {
      final source = '''
class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson($type json) =>
      ReportModel(id: (json["id"] ?? "").toString());
}
''';
      final result = parser.parse(source, 'supported_from_json.dart');

      expect(result.isSafe, isTrue,
          reason: '$type: ${result.diagnostics.join('\n')}');
    }
  });

  test('refuses direct nonnullable nested-model self and mutual cycles', () {
    const sources = {
      'self': '''
class NodeModel {
  final NodeModel child;
  NodeModel({required this.child});
  factory NodeModel.fromJson(Map<String, dynamic>? json) =>
      NodeModel(child: NodeModel.fromJson(json?["child"]));
}
''',
      'mutual': '''
class FirstModel {
  final SecondModel second;
  FirstModel({required this.second});
  factory FirstModel.fromJson(Map<String, dynamic>? json) =>
      FirstModel(second: SecondModel.fromJson(json?["second"]));
}
class SecondModel {
  final FirstModel first;
  SecondModel({required this.first});
  factory SecondModel.fromJson(Map<String, dynamic>? json) =>
      SecondModel(first: FirstModel.fromJson(json?["first"]));
}
''',
    };

    for (final entry in sources.entries) {
      final result = parser.parse(entry.value, '${entry.key}_cycle.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(result.diagnostics.join('\n'), contains('cycle'),
          reason: entry.key);
    }
  });

  test('derives acronym-safe snake-case keys and records their origin', () {
    const source = '''
class ReportModel {
  final String currentPage;
  final String URLValue;

  ReportModel({required this.currentPage, required this.URLValue});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        currentPage: "fallback",
        URLValue: "fallback",
      );
}
''';

    final result = parser.parse(source, 'derived_keys.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(
      result.spec!.classes.single.fields.map((field) => field.jsonKey),
      ['current_page', 'url_value'],
    );
    expect(
      result.spec!.classes.single.fields.map((field) => field.isJsonKeyDerived),
      [isTrue, isTrue],
    );
  });

  test('preserves an envelope factory and safely discovers aliased leaf keys',
      () {
    const factorySource = '''factory ReportModel.fromJson(
    Map<String, dynamic>? json,
  ) {
    final data = json?["data"];
    final items = data is Map<String, dynamic> ? data["items"] : null;
    final payload = items is Map<String, dynamic> ? items : const {};
    return ReportModel(
      id: (payload["report_id"] ?? "").toString(),
    );
  }''';
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  $factorySource
}
''';

    final result = parser.parse(source, 'aliased_envelope.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    final model = result.spec!.classes.single;
    expect(model.fields.single.jsonKey, 'report_id');
    expect(model.preservedFromJson, factorySource);
    expect(model.supportsDirectObjectFromJson, isFalse);
  });

  test('preserves helper-wrapped JSON aliases instead of flattening them', () {
    const factorySource = '''factory ReportModel.fromJson(
    Map<String, dynamic>? json,
  ) {
    final payload = _payload(json);
    return ReportModel(
      id: (payload["report_id"] ?? "").toString(),
    );
  }''';
    const source = '''
class ReportModel {
  final String id;

  ReportModel({required this.id});

  $factorySource
}

Map<String, dynamic> _payload(Map<String, dynamic>? json) {
  final data = json?["data"];
  return data is Map<String, dynamic> ? data : const {};
}
''';

    final result = parser.parse(source, 'wrapped_alias.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    final model = result.spec!.classes.single;
    expect(model.fields.single.jsonKey, 'report_id');
    expect(model.fields.single.isJsonKeyDerived, isFalse);
    expect(model.preservedFromJson, factorySource);
    expect(model.supportsDirectObjectFromJson, isFalse);
  });

  test('resolves bare local aliases through data and data.items envelopes', () {
    const cases = {
      'data': '''
class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson(Map<String, dynamic>? json) {
    final data = json?["data"];
    final rawId = data is Map<String, dynamic>
        ? data["report_id"]
        : null;
    return ReportModel(id: (rawId ?? "").toString());
  }
}
''',
      'data.items': '''
class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson(Map<String, dynamic>? json) {
    final data = json?["data"];
    final items = data is Map<String, dynamic> ? data["items"] : null;
    final payload = items is Map<String, dynamic> ? items : const {};
    final rawId = payload["report_id"];
    return ReportModel(id: (rawId ?? "").toString());
  }
}
''',
    };

    for (final entry in cases.entries) {
      final result = parser.parse(entry.value, '${entry.key}_bare_alias.dart');

      expect(result.isSafe, isTrue,
          reason: '${entry.key}: ${result.diagnostics.join('\n')}');
      final model = result.spec!.classes.single;
      expect(model.fields.single.jsonKey, 'report_id', reason: entry.key);
      expect(model.fields.single.isJsonKeyDerived, isFalse, reason: entry.key);
      expect(model.preservedFromJson, isNotNull, reason: entry.key);
      expect(model.supportsDirectObjectFromJson, isFalse, reason: entry.key);
    }
  });

  test('refuses ambiguous, reassigned, and cyclic bare local aliases', () {
    const factoryBodies = {
      'reassigned': '''
    var data = json?["data"];
    data = json?["legacy"];
    final rawId = data?["report_id"];
    return ReportModel(id: (rawId ?? "").toString());''',
      'multiple definitions': '''
    final rawId = json?["report_id"];
    final rawId = json?["legacy_id"];
    return ReportModel(id: (rawId ?? "").toString());''',
      'cycle': '''
    final first = second;
    final second = first;
    return ReportModel(id: (first ?? "").toString());''',
      'mutation': '''
    final data = json?["data"];
    if (data is Map<String, dynamic>) {
      data["report_id"] = "changed";
    }
    final rawId = data is Map<String, dynamic>
        ? data["report_id"]
        : null;
    return ReportModel(id: (rawId ?? "").toString());''',
      'non-resolvable': '''
    final rawId = unresolvedValue();
    return ReportModel(id: (rawId ?? "").toString());''',
    };

    for (final entry in factoryBodies.entries) {
      final source = '''
class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson(Map<String, dynamic>? json) {
${entry.value}
  }
}
''';
      final result = parser.parse(source, '${entry.key}_alias.dart');

      expect(result.isSafe, isFalse, reason: entry.key);
      expect(result.spec, isNull, reason: entry.key);
      expect(result.diagnostics.join('\n'), contains('ReportModel.id'),
          reason: entry.key);
      expect(result.diagnostics.join('\n'), contains('alias'),
          reason: entry.key);
    }
  });

  test('records exact supported top-level root helper roles from the AST', () {
    final source = File('test/fixtures/models/direct_list_helpers.dart')
        .readAsStringSync();

    final result = parser.parse(source, 'direct_list_helpers.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
    expect(
      result.spec!.topLevelFunctions.map((function) => function.role),
      [
        ModelTopLevelFunctionRole.rootDecoder,
        ModelTopLevelFunctionRole.rootEncoder,
      ],
    );
  });

  test('refuses a same-name top-level helper with an unsupported shape', () {
    const source = '''
int reportModelFromJson(int value) => value;

class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      ReportModel(id: (json?["id"] ?? "").toString());
}
''';

    final result = parser.parse(source, 'invalid_root_helper.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('reportModelFromJson'));
  });

  test('allows nullable nested-model links that break recursive defaults', () {
    const source = '''
class NodeModel {
  final NodeModel? child;
  NodeModel({required this.child});
  factory NodeModel.fromJson(Map<String, dynamic>? json) => NodeModel(
        child: json?["child"] == null
            ? null
            : NodeModel.fromJson(json?["child"]),
      );
}
''';

    final result = parser.parse(source, 'nullable_link.dart');

    expect(result.isSafe, isTrue, reason: result.diagnostics.join('\n'));
  });

  test('refuses an invalid fromJson contract on a zero-field class', () {
    const source = '''
class EmptyModel {
  factory EmptyModel.fromJson(int json) => EmptyModel();
}
''';

    final result = parser.parse(source, 'empty_invalid_from_json.dart');

    expect(result.isSafe, isFalse);
    expect(result.spec, isNull);
    expect(result.diagnostics.join('\n'), contains('EmptyModel.fromJson'));
  });
}
