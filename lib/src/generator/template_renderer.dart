import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/dependency_manifest.dart';
import '../config/project_answers.dart';
import '../format/text_escaping.dart';
import '../templates/api_templates.dart';
import '../templates/auth_templates.dart';
import '../templates/base_templates.dart';
import '../templates/sample_api_templates.dart';

abstract interface class ProjectTemplateRenderer {
  Future<void> render({
    required Directory projectRoot,
    required ProjectAnswers answers,
  });
}

final class TemplateRenderer implements ProjectTemplateRenderer {
  const TemplateRenderer({DependencyManifest? dependencyManifest})
      : _dependencyManifest = dependencyManifest ?? const DependencyManifest();

  final DependencyManifest _dependencyManifest;

  @override
  Future<void> render({
    required Directory projectRoot,
    required ProjectAnswers answers,
  }) async {
    final tokens = {
      '{{display_name}}': answers.displayName,
      '{{display_name_dart}}': TextEscaping.dartSingleQuoted(
        answers.displayName,
      ),
      '{{project_name}}': answers.projectName,
      '{{application_id}}': answers.applicationId,
      '{{uses_api}}': answers.usesApi ? 'yes' : 'no',
      '{{uses_authentication}}': answers.usesAuthentication ? 'yes' : 'no',
      '{{uses_refresh_tokens}}': answers.usesRefreshTokens ? 'yes' : 'no',
      '{{includes_sample_api}}': answers.includesSampleApi ? 'yes' : 'no',
      '{{api_base_url}}': answers.apiBaseUri?.toString() ?? '',
      '{{sample_route_import}}': answers.includesSampleApi
          ? "import '../../core/route/app_router.dart';"
          : '',
      '{{sample_action_widget}}': answers.includesSampleApi
          ? '''
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('sample-api-action'),
              onPressed: _handleOpenSampleApi,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Open sample API'),
            ),'''
          : '',
      '{{sample_action_handler}}': answers.includesSampleApi
          ? '''

  void _handleOpenSampleApi() {
    context.router.push(const SampleItemsRoute());
  }'''
          : '',
    };

    final templates = <String, String>{
      ...baseTemplates,
      if (answers.usesApi) ...apiTemplates,
      if (answers.usesAuthentication) ...authTemplates,
      if (answers.usesRefreshTokens) ...refreshTokenTemplates,
      if (answers.includesSampleApi) ...sampleApiTemplates,
    };
    for (final template in templates.entries) {
      await _write(
        projectRoot,
        template.key,
        _replaceTokens(template.value, tokens),
      );
    }
    await _write(
      projectRoot,
      'pubspec.yaml',
      _dependencyManifest.render(answers),
    );
    await _writePlaceholderReadmes(projectRoot);
  }

  String _replaceTokens(String input, Map<String, String> tokens) {
    var output = input;
    for (final token in tokens.entries) {
      output = output.replaceAll(token.key, token.value);
    }
    return output;
  }

  Future<void> _write(
    Directory root,
    String relativePath,
    String content,
  ) async {
    final file = File(p.join(root.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content.endsWith('\n') ? content : '$content\n');
  }

  Future<void> _writePlaceholderReadmes(Directory root) async {
    const folders = <String, String>{
      'assets/fonts':
          'Place licensed font files here and register real families in pubspec.yaml.',
      'assets/icons': 'Place raster application icons used by widgets here.',
      'assets/images': 'Place application image assets here.',
      'assets/svgs':
          'Place SVG assets here and add flutter_svg when the first SVG is used.',
      'lib/core/constant':
          'Application-wide constants and dependency providers live here.',
      'lib/core/exceptions':
          'Shared typed exception and failure contracts live here.',
      'lib/core/extensions': 'Small application-specific extensions live here.',
      'lib/core/localization':
          'Localization configuration and generated access helpers live here.',
      'lib/core/network':
          'Connectivity and low-level network configuration live here.',
      'lib/core/services':
          'Shared platform and transport service wrappers live here.',
      'lib/core/utils':
          'Focused utilities with no feature ownership live here.',
      'lib/domain/form_data':
          'Request payloads named *_form_param.dart live here.',
      'lib/domain/models': 'Immutable domain and API models live here.',
      'lib/data/local-storage':
          'Abstract and concrete local persistence sources live here.',
      'lib/data/remote-apis/abst_remote':
          'Abstract remote source contracts live here.',
      'lib/data/remote-apis/remote':
          'Concrete endpoint implementations live here.',
      'lib/data/repository_impl/abst_repository':
          'Abstract repository contracts live here.',
      'lib/data/repository_impl/repository':
          'Concrete repository implementations live here.',
    };
    for (final folder in folders.entries) {
      final readme = File(p.join(root.path, folder.key, 'README.md'));
      if (await readme.exists()) continue;
      await readme.parent.create(recursive: true);
      await readme.writeAsString('${folder.value}\n');
    }
  }
}
