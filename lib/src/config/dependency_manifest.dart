import 'project_answers.dart';
import '../format/text_escaping.dart';

final class DependencyManifest {
  const DependencyManifest();

  String render(ProjectAnswers answers) {
    final dependencies = <String>[
      '  flutter:',
      '    sdk: flutter',
      '  cupertino_icons: ^1.0.8',
      '  flutter_riverpod: ^3.4.2',
      '  auto_route: ^11.1.0',
    ];
    if (answers.usesApi) {
      dependencies.addAll([
        '  dio: ^5.9.0',
        '  dartz: ^0.10.1',
        '  internet_connection_checker_plus: ^2.7.0',
      ]);
    }
    if (answers.usesAuthentication) {
      dependencies.add('  flutter_secure_storage: ^9.2.4');
    }

    final description = TextEscaping.yamlDoubleQuoted(answers.displayName);
    return '''
name: ${answers.projectName}
description: "$description Flutter application."
publish_to: none
version: 0.1.0+1

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
${dependencies.join('\n')}

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  auto_route_generator: ^10.6.0
  build_runner: ^2.15.1

flutter:
  uses-material-design: true
  assets:
    - assets/fonts/
    - assets/icons/
    - assets/images/
    - assets/svgs/
''';
  }
}
