import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:gold_flutter/src/model/dart_model_parser.dart';
import 'package:gold_flutter/src/model/eyeask_model_renderer.dart';
import 'package:test/test.dart';

void main() {
  const parser = DartModelParser();

  test('renders the approved EyeAsk model style exactly', () {
    final inputSource =
        File('test/fixtures/models/eyeask_input.dart').readAsStringSync();
    final expectedSource =
        File('test/fixtures/models/eyeask_expected.dart').readAsStringSync();
    final parsed = parser.parse(inputSource, 'eyeask_input.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );

    expect(rendered, expectedSource);
  });

  test('preserves an existing copyWith and custom source exactly once', () {
    const source = r'''
import 'package:meta/meta.dart';

/// A report from the API.
@immutable
class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  ReportModel copyWith({String? id}) {
    return ReportModel(id: id ?? this.id);
  }

  String get label => id;
}
''';
    const existingCopyWith = '''ReportModel copyWith({String? id}) {
    return ReportModel(id: id ?? this.id);
  }''';
    final parsed = parser.parse(source, 'existing_copy_with.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: true,
    );

    expect(existingCopyWith.allMatches(rendered), hasLength(1));
    expect(rendered, contains("import 'package:meta/meta.dart';"));
    expect(rendered, contains('/// A report from the API.\n@immutable'));
    expect(rendered, contains('String get label => id;'));
  });

  test('omits a missing copyWith when it is not requested', () {
    const source = r'''
class NoteModel {
  final String? note;

  NoteModel({required this.note});

  factory NoteModel.fromJson(Map<String, dynamic>? json) => NoteModel(
        note: (json?["note"] ?? "").toString(),
      );
}
''';
    final parsed = parser.parse(source, 'note_model.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );

    expect(rendered, isNot(contains('copyWith')));
  });

  test('generates requested copyWith and keeps nullable values for null', () {
    const source = r'''
class NoteModel {
  final String? note;

  NoteModel({required this.note});

  factory NoteModel.fromJson(Map<String, dynamic>? json) => NoteModel(
        note: (json?["note"] ?? "").toString(),
      );
}
''';
    const expectedCopyWith = '''NoteModel copyWith({
    String? note,
  }) {
    return NoteModel(
      note: note ?? this.note,
    );
  }''';
    final parsed = parser.parse(source, 'note_model.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: true,
    );

    expect(rendered, contains(expectedCopyWith));
  });

  test('uses and preserves the existing enum converter without inventing one',
      () {
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
    const converter = '''Status _statusFromJson(dynamic value) {
  return Status.values.firstWhere(
    (status) => status.name == value?.toString(),
    orElse: () => Status.inactive,
  );
}''';
    final parsed = parser.parse(source, 'enum_model.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );

    expect(converter.allMatches(rendered), hasLength(1));
    expect(rendered, contains('status: _statusFromJson(json?["status"]),'));
    expect(rendered, contains('"status": status.name,'));
  });

  test('escapes adversarial JSON keys without changing runtime values', () {
    const source = r'''
class WeirdKeysModel {
  final String quoted;
  final String slashed;
  final String cash;
  final String lined;
  final String returned;
  final String tabbed;
  final String controlled;

  WeirdKeysModel({
    required this.quoted,
    required this.slashed,
    required this.cash,
    required this.lined,
    required this.returned,
    required this.tabbed,
    required this.controlled,
  });

  factory WeirdKeysModel.fromJson(Map<String, dynamic>? json) =>
      WeirdKeysModel(
        quoted: (json?["quote\"key"] ?? "").toString(),
        slashed: (json?["slash\\key"] ?? "").toString(),
        cash: (json?["\$cash"] ?? "").toString(),
        lined: (json?["line\nkey"] ?? "").toString(),
        returned: (json?["carriage\rkey"] ?? "").toString(),
        tabbed: (json?["tab\tkey"] ?? "").toString(),
        controlled: (json?["control\u0001key"] ?? "").toString(),
      );
}
''';
    const escapedKeys = [
      r'"quote\"key"',
      r'"slash\\key"',
      r'"\$cash"',
      r'"line\nkey"',
      r'"carriage\rkey"',
      r'"tab\tkey"',
      r'"control\u{1}key"',
    ];
    const runtimeKeys = [
      'quote"key',
      r'slash\key',
      r'$cash',
      'line\nkey',
      'carriage\rkey',
      'tab\tkey',
      'control\u0001key',
    ];
    final parsed = parser.parse(source, 'weird_keys.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );
    final generated = parseString(
      content: rendered,
      path: 'weird_keys_rendered.dart',
      throwIfDiagnostics: false,
    );
    final literals = _StringLiteralVisitor();
    generated.unit.accept(literals);

    expect(
      generated.errors,
      isEmpty,
      reason: generated.errors.map((error) => error.message).join('\n'),
    );
    for (final escapedKey in escapedKeys) {
      expect(escapedKey.allMatches(rendered), hasLength(2));
    }
    expect(literals.values, containsAll(runtimeKeys));
  });

  test('renders an analyzer-clean structural API for a zero-field root',
      () async {
    const source = 'class EmptyModel {}';
    final parsed = parser.parse(source, 'empty_model.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );

    expect(rendered, contains('  EmptyModel();'));
    expect(
      rendered,
      contains(
        'factory EmptyModel.fromJson(Map<String, dynamic>? json) => '
        'EmptyModel();',
      ),
    );
    expect(rendered, contains('factory EmptyModel.empty() => EmptyModel();'));
    expect(
      rendered,
      contains('Map<String, dynamic> toJson() => {};'),
    );
    await _expectAnalyzerClean(rendered);
  });

  test('renders analyzer-clean nested references to a zero-field class',
      () async {
    const source = '''
class RootModel {
  final EmptyModel empty;

  RootModel({required this.empty});

  factory RootModel.fromJson(Map<String, dynamic>? json) => RootModel(
        empty: EmptyModel.fromJson(json?["empty"]),
      );
}

class EmptyModel {}
''';
    final parsed = parser.parse(source, 'nested_empty_model.dart');

    expect(parsed.isSafe, isTrue, reason: parsed.diagnostics.join('\n'));

    final rendered = const EyeAskModelRenderer().render(
      parsed.spec!,
      addCopyWith: false,
    );

    expect(rendered, contains('empty: EmptyModel.fromJson(json?["empty"]),'));
    expect(rendered, contains('empty: EmptyModel.empty(),'));
    expect(rendered, contains('class EmptyModel {\n\n  EmptyModel();'));
    await _expectAnalyzerClean(rendered);
  });
}

Future<void> _expectAnalyzerClean(String source) async {
  final directory = Directory.systemTemp.createTempSync('eyeask-renderer-');
  try {
    final file = File('${directory.path}/generated.dart')
      ..writeAsStringSync(source);
    final result = await resolveFile2(path: file.path);

    expect(result, isA<ResolvedUnitResult>(), reason: result.toString());
    final resolved = result as ResolvedUnitResult;
    expect(
      resolved.errors,
      isEmpty,
      reason: resolved.errors.map((error) => error.message).join('\n'),
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

final class _StringLiteralVisitor extends RecursiveAstVisitor<void> {
  final values = <String>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    values.add(node.value);
    super.visitSimpleStringLiteral(node);
  }
}
