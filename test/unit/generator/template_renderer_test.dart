import 'dart:io';

import 'package:gold_flutter/src/generator/template_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../support/project_answers_fixtures.dart';

void main() {
  test('renders the complete base foundation and project skill', () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: baseAnswers,
    );

    expect(
      File(p.join(root.path, 'lib/main.dart')).readAsStringSync(),
      contains('ProviderScope'),
    );
    expect(
      File(p.join(root.path, 'lib/core/route/app_router.dart'))
          .readAsStringSync(),
      contains('AutoRouterConfig'),
    );
    expect(
      File(
        p.join(
          root.path,
          '.agents/skills/gold-flutter-development/SKILL.md',
        ),
      ).readAsStringSync(),
      allOf(contains('Riverpod 3'),
          contains('Do not add a global spacing class')),
    );
    expect(
      Directory(p.join(root.path, 'assets/images')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(root.path, 'lib/data/remote-apis')).existsSync(),
      isTrue,
    );
  });

  test('generated skill renders clean screen and Riverpod guidance smoke test',
      () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: baseAnswers,
    );

    final skill = File(
      p.join(
        root.path,
        '.agents/skills/gold-flutter-development/SKILL.md',
      ),
    ).readAsStringSync();

    expect(
      skill,
      allOf([
        contains('smallest widget boundary that renders it'),
        contains('smallest-boundary rule takes precedence'),
        contains('`lib/presentation/widgets/<feature>/`'),
        matches(RegExp(r'descriptive public\s+name')),
        contains('secondary provider subscriptions'),
        contains('event-time `ref.read(provider)`'),
        contains('`select`'),
        contains('`Provider.autoDispose.family`'),
        contains('`package:provider`'),
        contains('rebuild-isolation tests'),
      ]),
    );
  });

  test('starter screen models focused Riverpod and widget ownership', () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: baseAnswers,
    );

    final screen = File(
      p.join(root.path, 'lib/presentation/screens/home_screen.dart'),
    ).readAsStringSync();
    final header = File(
      p.join(
        root.path,
        'lib/presentation/widgets/home/home_counter_header.dart',
      ),
    ).readAsStringSync();
    final grid = File(
      p.join(
        root.path,
        'lib/presentation/widgets/home/home_foundation_grid.dart',
      ),
    ).readAsStringSync();

    expect(screen, contains('class HomeScreen extends StatelessWidget'));
    expect(screen, isNot(contains('ref.watch')));
    expect(screen, contains('const HomeCounterHeader()'));
    expect(screen, contains('const HomeFoundationGrid()'));
    expect(header, contains('class HomeCounterHeader extends ConsumerWidget'));
    expect(header, contains('ref.watch(starterViewModelProvider)'));
    expect(
      header,
      contains('ref.read(starterViewModelProvider.notifier).increment()'),
    );
    expect(grid, contains('class HomeFoundationGrid extends StatelessWidget'));
    expect(grid, isNot(contains('flutter_riverpod')));
  });

  test('replaces project tokens in rendered files', () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: baseAnswers,
    );

    final readme = File(p.join(root.path, 'README.md')).readAsStringSync();
    expect(readme, contains('My Parking App'));
    expect(readme, contains('com.company.parking'));
    expect(readme, isNot(contains('{{')));
  });

  test('escapes display names in generated Dart and YAML', () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));
    final answers = baseAnswers.copyWith(
      displayName: r'''Bob's R&D "Clock" $5''',
    );

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: answers,
    );

    final app = File(p.join(root.path, 'lib/app.dart')).readAsStringSync();
    expect(app, contains(r'''title: 'Bob\'s R&D "Clock" \$5' '''.trim()));
    final manifest = loadYaml(
      File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
    ) as YamlMap;
    expect(
      manifest['description'],
      r'''Bob's R&D "Clock" $5 Flutter application.''',
    );
  });

  test('API variant renders transport layers without authentication', () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: apiNoAuthAnswers,
    );

    expect(
        File(p.join(root.path, 'lib/core/services/services.dart')).existsSync(),
        isTrue);
    expect(
        File(p.join(root.path, 'lib/core/network/network_info.dart'))
            .existsSync(),
        isTrue);
    expect(
      File(p.join(root.path, 'lib/core/network/token_storage.dart'))
          .existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(root.path, 'lib/core/exceptions/api_exception.dart'),
      ).readAsStringSync(),
      contains('DioExceptionType.transformTimeout'),
    );
  });

  test('authentication and refresh choices render only their infrastructure',
      () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: authenticatedAnswers,
    );

    expect(
        File(p.join(root.path, 'lib/core/network/token_storage.dart'))
            .existsSync(),
        isTrue);
    expect(
      File(p.join(root.path, 'lib/core/network/token_refresh_coordinator.dart'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(
          root.path,
          'test/core/network/authorization_interceptor_test.dart',
        ),
      ).readAsStringSync(),
      contains('dio: dio'),
    );
  });

  test('sample API choice renders every architectural seam and screen',
      () async {
    final root = await Directory.systemTemp.createTemp('gold_template_test_');
    addTearDown(() => root.delete(recursive: true));

    await const TemplateRenderer().render(
      projectRoot: root,
      answers: apiSampleAnswers,
    );

    for (final path in [
      'lib/domain/models/sample_item_model.dart',
      'lib/data/remote-apis/abst_remote/sample_remote_data_source.dart',
      'lib/data/remote-apis/remote/sample_remote_data_source_impl.dart',
      'lib/data/repository_impl/abst_repository/sample_repository.dart',
      'lib/data/repository_impl/repository/sample_repository_impl.dart',
      'lib/business/sample/sample_items_viewmodel.dart',
      'lib/presentation/screens/sample_items_screen.dart',
    ]) {
      expect(File(p.join(root.path, path)).existsSync(), isTrue, reason: path);
    }
    final homeScreen =
        File(p.join(root.path, 'lib/presentation/screens/home_screen.dart'))
            .readAsStringSync();
    expect(
      homeScreen,
      allOf(
        contains("import '../../core/route/app_router.dart';"),
        isNot(contains("import '../../core/route/app_router.gr.dart';")),
        contains('SampleItemsRoute'),
        contains('context.router.push(const SampleItemsRoute())'),
      ),
    );
    expect(
      File(
        p.join(
          root.path,
          'lib/presentation/widgets/home/home_counter_header.dart',
        ),
      ).readAsStringSync(),
      allOf(
        contains("Key('sample-api-action')"),
        contains('Open sample API'),
      ),
    );
  });
}
