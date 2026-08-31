import 'package:gold_flutter/src/model/model_class_spec.dart';
import 'package:gold_flutter/src/model/model_file_spec.dart';
import 'package:gold_flutter/src/model/model_field_spec.dart';
import 'package:test/test.dart';

void main() {
  test('model specs preserve source ordering and cannot be mutated', () {
    final spec = ModelClassSpec(
      name: 'UserModel',
      fields: [
        ModelFieldSpec(
          name: 'id',
          typeSource: 'String',
          jsonKey: 'id',
          kind: ModelFieldKind.string,
          isNullable: false,
          nestedType: null,
          sourceOffset: 10,
        ),
      ],
      annotations: const [],
      documentation: null,
      preservedMembers: const [],
      hasCopyWith: false,
      sourceOffset: 0,
    );

    expect(spec.fields.single.name, 'id');
    expect(() => spec.fields.add(spec.fields.single), throwsUnsupportedError);
  });

  test('model specs defensively copy every source-ordered collection', () {
    final field = ModelFieldSpec(
      name: 'id',
      typeSource: 'String',
      jsonKey: 'id',
      kind: ModelFieldKind.string,
      isNullable: false,
      nestedType: null,
      sourceOffset: 10,
    );
    final fields = [field];
    final annotations = ['@JsonSerializable()'];
    final members = ['String get label => id;'];
    final classes = [
      ModelClassSpec(
        name: 'UserModel',
        fields: fields,
        annotations: annotations,
        documentation: 'A user.',
        preservedMembers: members,
        hasCopyWith: false,
        sourceOffset: 0,
      ),
    ];
    final imports = ["import 'dart:convert';"];
    final declarations = ['String encodeUser(UserModel value) => value.id;'];
    final file = ModelFileSpec(
      imports: imports,
      rootClassName: 'UserModel',
      classes: classes,
      preservedTopLevelDeclarations: declarations,
    );

    fields.clear();
    annotations.clear();
    members.clear();
    classes.clear();
    imports.clear();
    declarations.clear();

    expect(file.classes.single.fields.single.name, 'id');
    expect(file.classes.single.annotations, ['@JsonSerializable()']);
    expect(file.classes.single.preservedMembers, ['String get label => id;']);
    expect(file.imports, ["import 'dart:convert';"]);
    expect(file.preservedTopLevelDeclarations, [
      'String encodeUser(UserModel value) => value.id;',
    ]);
    expect(() => file.classes.clear(), throwsUnsupportedError);
    expect(() => file.imports.clear(), throwsUnsupportedError);
    expect(
      () => file.preservedTopLevelDeclarations.clear(),
      throwsUnsupportedError,
    );
  });

  test('model specs reject missing required identifiers and nested metadata',
      () {
    expect(
      () => ModelFieldSpec(
        name: '',
        typeSource: 'String',
        jsonKey: 'id',
        kind: ModelFieldKind.string,
        isNullable: false,
        nestedType: null,
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'id',
        typeSource: '',
        jsonKey: 'id',
        kind: ModelFieldKind.string,
        isNullable: false,
        nestedType: null,
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'user',
        typeSource: 'UserModel',
        jsonKey: 'user',
        kind: ModelFieldKind.nestedModel,
        isNullable: false,
        nestedType: '',
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'user',
        typeSource: 'UserModel',
        jsonKey: 'user',
        kind: ModelFieldKind.nestedModel,
        isNullable: false,
        nestedType: null,
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'users',
        typeSource: 'List<UserModel>',
        jsonKey: 'users',
        kind: ModelFieldKind.list,
        isNullable: false,
        nestedType: null,
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'users',
        typeSource: 'List<UserModel>',
        jsonKey: 'users',
        kind: ModelFieldKind.list,
        isNullable: false,
        nestedType: '',
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'status',
        typeSource: 'Status',
        jsonKey: 'status',
        kind: ModelFieldKind.enumeration,
        isNullable: false,
        nestedType: null,
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFieldSpec(
        name: 'status',
        typeSource: 'Status',
        jsonKey: 'status',
        kind: ModelFieldKind.enumeration,
        isNullable: false,
        nestedType: '',
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelClassSpec(
        name: '',
        fields: const [],
        annotations: const [],
        documentation: null,
        preservedMembers: const [],
        hasCopyWith: false,
        sourceOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ModelFileSpec(
        imports: const [],
        rootClassName: '',
        classes: const [],
        preservedTopLevelDeclarations: const [],
      ),
      throwsArgumentError,
    );
  });
}
