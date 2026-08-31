import 'dart:io';

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
}
