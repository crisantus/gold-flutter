import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:gold_flutter/src/model/dart_model_parser.dart';
import 'package:gold_flutter/src/model/eyeask_model_renderer.dart';
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

  test('renders analyzer-valid defensive and round-trip model tests', () async {
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
    expect(rendered, contains('json.encode(original.toJson())'));
    expect(
      rendered,
      contains(
        'ReportModel.fromJson(\n'
        '        json.decode(encoded) as Map<String, dynamic>,',
      ),
    );
    expect(rendered, isNot(contains('reportModelToJson(original)')));
    expect(rendered, isNot(contains('reportModelFromJson(encoded)')));
    expect(
      syntax.errors,
      isEmpty,
      reason: syntax.errors.map((error) => error.message).join('\n'),
    );
    await _expectAnalyzerCleanPackage(
      modelSource: const EyeAskModelRenderer().render(
        parsed.spec!,
        addCopyWith: false,
      ),
      testSource: rendered,
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

  test('allows null or the enum type only for nullable enum fallbacks', () {
    final spec = ModelFileSpec(
      imports: const [],
      rootClassName: 'ReportModel',
      classes: [
        ModelClassSpec(
          name: 'ReportModel',
          fields: [
            ModelFieldSpec(
              name: 'optionalStatus',
              typeSource: 'Status?',
              jsonKey: 'optional_status',
              kind: ModelFieldKind.enumeration,
              isNullable: true,
              nestedType: 'Status',
              sourceOffset: 0,
            ),
            ModelFieldSpec(
              name: 'requiredStatus',
              typeSource: 'Status',
              jsonKey: 'required_status',
              kind: ModelFieldKind.enumeration,
              isNullable: false,
              nestedType: 'Status',
              sourceOffset: 1,
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

    expect(
      rendered,
      contains(
        'expect(missing.optionalStatus, '
        'anyOf(isNull, isA<Status>()));',
      ),
    );
    expect(
      rendered,
      contains(
        'expect(nulls.optionalStatus, '
        'anyOf(isNull, isA<Status>()));',
      ),
    );
    expect(
      rendered,
      contains('expect(missing.requiredStatus, isA<Status>());'),
    );
    expect(
      rendered,
      contains('expect(nulls.requiredStatus, isA<Status>());'),
    );
  });

  test('roundtrip remains analyzer-clean with preserved list root helpers',
      () async {
    final source = File('test/fixtures/models/direct_list_helpers.dart')
        .readAsStringSync();
    final parsed = parser.parse(source, 'direct_list_helpers.dart');
    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final modelSource = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );
    final testSource = renderer.render(
      parsed.spec!,
      modelImport: 'package:fixture/domain/models/report_model.dart',
    );

    expect(testSource, contains('json.encode(original.toJson())'));
    expect(testSource, isNot(contains('reportModelFromJson(encoded)')));
    await _expectAnalyzerCleanPackage(
      modelSource: modelSource,
      testSource: testSource,
    );
  });

  test('refuses test rendering when no public root exists', () {
    const source = '''
class _PrivateModel {
  final String id;
  _PrivateModel({required this.id});
  factory _PrivateModel.fromJson(Map<String, dynamic>? json) =>
      _PrivateModel(id: (json?["id"] ?? "").toString());
}
''';
    final parsed = parser.parse(source, 'private_only.dart');
    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    expect(
      () => renderer.render(
        parsed.spec!,
        modelImport: 'package:fixture/private_only.dart',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('public root'),
        ),
      ),
    );
  });

  test('refuses direct-object tests for a preserved envelope factory', () {
    const source = '''
class ReportModel {
  final String id;
  ReportModel({required this.id});
  factory ReportModel.fromJson(Map<String, dynamic>? json) {
    final data = json?["data"];
    final payload = data is Map<String, dynamic> ? data : const {};
    return ReportModel(id: (payload["id"] ?? "").toString());
  }
}
''';
    final parsed = parser.parse(source, 'envelope_factory.dart');
    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    expect(
      () => renderer.render(
        parsed.spec!,
        modelImport: 'package:fixture/envelope_factory.dart',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('direct-object'),
        ),
      ),
    );
  });

  test('uses the first public class for an analyzer-clean generated test',
      () async {
    const source = '''
class _PrivatePayload {
  final String id;
  _PrivatePayload({required this.id});
  factory _PrivatePayload.fromJson(Map<String, dynamic>? json) =>
      _PrivatePayload(id: (json?["id"] ?? "").toString());
}

class ReportModel {
  final String title;
  ReportModel({required this.title});
  factory ReportModel.fromJson(Map<String, dynamic>? json) =>
      ReportModel(title: (json?["title"] ?? "").toString());
}
''';
    final parsed = parser.parse(source, 'first_public_root.dart');
    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final modelSource = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );
    final testSource = renderer.render(
      parsed.spec!,
      modelImport: 'package:fixture/domain/models/report_model.dart',
    );

    expect(testSource, contains("group('ReportModel'"));
    expect(testSource, isNot(contains('_PrivatePayload')));
    expect(
      modelSource.indexOf('class _PrivatePayload'),
      lessThan(modelSource.indexOf('class ReportModel')),
    );
    await _expectAnalyzerCleanPackage(
      modelSource: modelSource,
      testSource: testSource,
    );
  });
}

Future<void> _expectAnalyzerCleanPackage({
  required String modelSource,
  required String testSource,
}) async {
  final root = await Directory.systemTemp.createTemp('model-test-renderer-');
  try {
    final model = File(
      '${root.path}/lib/domain/models/report_model.dart',
    );
    final test = File(
      '${root.path}/test/domain/models/report_model_test.dart',
    );
    final flutterTest = File(
      '${root.path}/fake_flutter_test/lib/flutter_test.dart',
    );
    final packageConfig = File(
      '${root.path}/.dart_tool/package_config.json',
    );
    await model.parent.create(recursive: true);
    await test.parent.create(recursive: true);
    await flutterTest.parent.create(recursive: true);
    await packageConfig.parent.create(recursive: true);
    await model.writeAsString(modelSource);
    await test.writeAsString(testSource);
    await flutterTest.writeAsString(_fakeFlutterTest);
    await packageConfig.writeAsString(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.5',
          },
          {
            'name': 'flutter_test',
            'rootUri': '../fake_flutter_test/',
            'packageUri': 'lib/',
            'languageVersion': '3.5',
          },
        ],
      }),
    );

    final contexts = AnalysisContextCollection(includedPaths: [root.path]);
    final result = await contexts
        .contextFor(test.path)
        .currentSession
        .getResolvedUnit(test.path);

    expect(result, isA<ResolvedUnitResult>(), reason: result.toString());
    final resolved = result as ResolvedUnitResult;
    expect(
      resolved.errors,
      isEmpty,
      reason: resolved.errors.map((error) => error.message).join('\n'),
    );
  } finally {
    await root.delete(recursive: true);
  }
}

const _fakeFlutterTest = r'''
void group(String description, void Function() body) => body();
void test(String description, void Function() body) {}
void expect(Object? actual, Object? matcher) {}
Object isA<T>() => Object();
Object anyOf(Object? first, Object? second) => Object();
final isNull = Object();
final isFalse = Object();
final isEmpty = Object();
''';
