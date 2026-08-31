import 'dart:convert';
import 'dart:io';

import 'package:gold_flutter/src/platform/app_identity.dart';
import 'package:gold_flutter/src/platform/platform_patcher.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('applies exact application id and display name to generated files',
      () async {
    final root = await Directory.systemTemp.createTemp('gold_identity_test_');
    addTearDown(() => root.delete(recursive: true));
    await _write(
      root,
      'android/app/build.gradle.kts',
      'namespace = "com.company.my_app"\napplicationId = "com.company.my_app"',
    );
    await _write(
      root,
      'android/app/src/main/AndroidManifest.xml',
      '<application android:label="my_app" />',
    );
    await _write(
      root,
      'android/app/src/main/kotlin/com/company/my_app/MainActivity.kt',
      'package com.company.my_app\n\nclass MainActivity',
    );
    await _write(
      root,
      'ios/Runner.xcodeproj/project.pbxproj',
      'PRODUCT_BUNDLE_IDENTIFIER = com.company.myApp;',
    );
    await _write(
      root,
      'web/manifest.json',
      '{"name":"my_app","short_name":"my_app"}',
    );
    await _write(
      root,
      'linux/CMakeLists.txt',
      'set(BINARY_NAME "my_app")\nset(APPLICATION_ID "com.company.my_app")',
    );

    await const PlatformPatcher().apply(
      projectRoot: root,
      identity: const AppIdentity(
        displayName: 'My App',
        projectName: 'my_app',
        applicationId: 'com.company.product',
      ),
    );

    expect(
      File(p.join(root.path, 'android/app/build.gradle.kts'))
          .readAsStringSync(),
      contains('com.company.product'),
    );
    expect(
      File(
        p.join(root.path, 'android/app/src/main/AndroidManifest.xml'),
      ).readAsStringSync(),
      contains('android:label="My App"'),
    );
    final mainActivity = File(
      p.join(
        root.path,
        'android/app/src/main/kotlin/com/company/product/MainActivity.kt',
      ),
    );
    expect(mainActivity.existsSync(), isTrue);
    expect(mainActivity.readAsStringSync(),
        contains('package com.company.product'));
    expect(
      File(
        p.join(
          root.path,
          'android/app/src/main/kotlin/com/company/my_app/MainActivity.kt',
        ),
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(root.path, 'ios/Runner.xcodeproj/project.pbxproj'),
      ).readAsStringSync(),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.company.product;'),
    );
    final manifest = jsonDecode(
      File(p.join(root.path, 'web/manifest.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['name'], 'My App');
    expect(manifest['short_name'], 'My App');
    expect(
      File(p.join(root.path, 'linux/CMakeLists.txt')).readAsStringSync(),
      allOf(contains('BINARY_NAME "my_app"'), contains('com.company.product')),
    );
  });

  test('replaces Flutter Apple identifiers without guessing camel case',
      () async {
    final root = await Directory.systemTemp.createTemp('gold_identity_test_');
    addTearDown(() => root.delete(recursive: true));
    await _write(
      root,
      'ios/Runner.xcodeproj/project.pbxproj',
      'PRODUCT_BUNDLE_IDENTIFIER = com.review.gfReviewComplete20260831a;\n'
          'PRODUCT_BUNDLE_IDENTIFIER = '
          'com.review.gfReviewComplete20260831a.RunnerTests;',
    );
    await _write(
      root,
      'macos/Runner/Configs/AppInfo.xcconfig',
      'PRODUCT_BUNDLE_IDENTIFIER = com.review.gfReviewComplete20260831a',
    );

    await const PlatformPatcher().apply(
      projectRoot: root,
      identity: const AppIdentity(
        displayName: 'Review Complete',
        projectName: 'gf_review_complete_20260831_a',
        applicationId: 'com.review.exactid',
      ),
    );

    expect(
      File(p.join(root.path, 'ios/Runner.xcodeproj/project.pbxproj'))
          .readAsStringSync(),
      allOf(
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.review.exactid;'),
        contains(
          'PRODUCT_BUNDLE_IDENTIFIER = com.review.exactid.RunnerTests;',
        ),
        isNot(contains('gfReviewComplete20260831a')),
      ),
    );
    expect(
      File(p.join(root.path, 'macos/Runner/Configs/AppInfo.xcconfig'))
          .readAsStringSync(),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.review.exactid'),
    );
  });

  test('escapes display names for platform file formats', () async {
    final root = await Directory.systemTemp.createTemp('gold_identity_test_');
    addTearDown(() => root.delete(recursive: true));
    await _write(
      root,
      'android/app/src/main/AndroidManifest.xml',
      '<application android:label="my_app" />',
    );
    await _write(
      root,
      'ios/Runner/Info.plist',
      '<dict><key>CFBundleDisplayName</key><string>my_app</string></dict>',
    );
    await _write(
      root,
      'web/manifest.json',
      '{"name":"my_app","short_name":"my_app"}',
    );
    await _write(
      root,
      'web/index.html',
      '<title>my_app</title>\n'
          '<meta name="apple-mobile-web-app-title" content="my_app">',
    );
    await _write(
      root,
      'linux/runner/my_application.cc',
      'gtk_window_set_title(window, "my_app");',
    );

    await const PlatformPatcher().apply(
      projectRoot: root,
      identity: const AppIdentity(
        displayName: 'Bob\'s R&D <Clock> "Plus"',
        projectName: 'my_app',
        applicationId: 'com.company.product',
      ),
    );

    expect(
      File(p.join(root.path, 'android/app/src/main/AndroidManifest.xml'))
          .readAsStringSync(),
      contains('Bob\'s R&amp;D &lt;Clock&gt; &quot;Plus&quot;'),
    );
    expect(
      File(p.join(root.path, 'ios/Runner/Info.plist')).readAsStringSync(),
      contains('Bob\'s R&amp;D &lt;Clock&gt; "Plus"'),
    );
    expect(
      File(p.join(root.path, 'web/index.html')).readAsStringSync(),
      allOf(
        contains('<title>Bob\'s R&amp;D &lt;Clock&gt; "Plus"</title>'),
        contains(
          'content="Bob&#39;s R&amp;D &lt;Clock&gt; &quot;Plus&quot;"',
        ),
      ),
    );
    expect(
      File(p.join(root.path, 'linux/runner/my_application.cc'))
          .readAsStringSync(),
      contains('"Bob\'s R&D <Clock> \\"Plus\\""'),
    );
  });
}

Future<void> _write(Directory root, String relativePath, String content) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
