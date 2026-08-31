import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:gold_flutter/src/model/dart_model_parser.dart';
import 'package:gold_flutter/src/model/model_class_spec.dart';
import 'package:gold_flutter/src/model/model_field_spec.dart';
import 'package:gold_flutter/src/model/model_file_spec.dart';
import 'package:gold_flutter/src/model/model_test_renderer.dart';
import 'package:test/test.dart';

void main() {
  const renderer = ModelTestRenderer();
  const parser = DartModelParser();

  test('derives the mirrored focused test path from the model path', () {
    expect(
      renderer.testPathFor('lib/domain/models/report_model.dart'),
      'test/domain/models/report_model_test.dart',
    );
  });

  test('renders analyzer-valid defensive and round-trip model tests', () {
    const source = r'''
class ReportModel {
  final String id;
  final int page;
  final bool ready;
  final DateTime createdAt;
  final UserModel user;
  final List<ItemModel> items;

  ReportModel({
    required this.id,
    required this.page,
    required this.ready,
    required this.createdAt,
    required this.user,
    required this.items,
  });

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
        page: int.tryParse((json?["current_page"] ?? "").toString()) ?? 0,
        ready: json?["ready"] is bool
            ? json!["ready"] as bool
            : (json?["ready"] ?? "").toString() == "true",
        createdAt: DateTime.tryParse(
              (json?["created_at"] ?? "").toString(),
            ) ??
            DateTime.now(),
        user: UserModel.fromJson(json?["user"]),
        items: (json?["items"] is List ? json!["items"] as List : [])
            .map((item) => ItemModel.fromJson(item))
            .toList(),
      );
}

class UserModel {
  final String name;

  UserModel({required this.name});

  factory UserModel.fromJson(Map<String, dynamic>? json) => UserModel(
        name: (json?["name"] ?? "").toString(),
      );
}

class ItemModel {
  final String sku;

  ItemModel({required this.sku});

  factory ItemModel.fromJson(Map<String, dynamic>? json) => ItemModel(
        sku: (json?["sku"] ?? "").toString(),
      );
}
''';
    final parsed = parser.parse(source, 'report_model.dart');
    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = renderer.render(
      parsed.spec!,
      modelImport: 'package:fixture/domain/models/report_model.dart',
    );
    final syntax = parseString(
      content: rendered,
      path: 'report_model_test.dart',
      throwIfDiagnostics: false,
    );

    expect(
      rendered.split('\n').first,
      ModelTestRenderer.ownershipMarker,
    );
    expect(
      rendered,
      contains(
        "import 'package:fixture/domain/models/report_model.dart';",
      ),
    );
    expect(rendered, contains("test('empty uses defensive defaults'"));
    expect(
      rendered,
      contains("test('null and missing primitive JSON uses safe defaults'"),
    );
    expect(
      rendered,
      contains("'current_page': null"),
    );
    expect(
      rendered,
      contains("test('nested and list JSON uses defensive fallbacks'"),
    );
    expect(rendered, contains("'items': 'not-a-list'"));
    expect(rendered, contains("test('JSON string round trip is stable'"));
    expect(rendered, contains('reportModelToJson(original)'));
    expect(rendered, contains('reportModelFromJson(encoded)'));
    expect(
      syntax.errors,
      isEmpty,
      reason: syntax.errors.map((error) => error.message).join('\n'),
    );
  });

  test('does not reference a nested type hidden behind the model library', () {
    final spec = ModelFileSpec(
      imports: const ["import 'user.dart' as dto;"],
      rootClassName: 'ReportModel',
      classes: [
        ModelClassSpec(
          name: 'ReportModel',
          fields: [
            ModelFieldSpec(
              name: 'user',
              typeSource: 'dto.UserModel',
              jsonKey: 'user',
              kind: ModelFieldKind.nestedModel,
              isNullable: false,
              nestedType: 'dto.UserModel',
              sourceOffset: 0,
            ),
          ],
          annotations: const [],
          documentation: null,
          preservedMembers: const [],
          hasCopyWith: false,
          sourceOffset: 0,
        ),
      ],
      preservedTopLevelDeclarations: const [],
    );

    final rendered = renderer.render(
      spec,
      modelImport: 'package:fixture/domain/models/report_model.dart',
    );

    expect(rendered, isNot(contains('dto.UserModel')));
    expect(
      rendered,
      contains('expect(value.user.toJson(), isA<Map<String, dynamic>>())'),
    );
  });
}
