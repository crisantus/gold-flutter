import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_identity.dart';

abstract interface class ProjectPlatformPatcher {
  Future<void> apply({
    required Directory projectRoot,
    required AppIdentity identity,
  });
}

final class PlatformPatcher implements ProjectPlatformPatcher {
  const PlatformPatcher();

  @override
  Future<void> apply({
    required Directory projectRoot,
    required AppIdentity identity,
  }) async {
    await _replaceInFiles(projectRoot, [
      'android/app/build.gradle',
      'android/app/build.gradle.kts',
      'ios/Runner.xcodeproj/project.pbxproj',
      'macos/Runner.xcodeproj/project.pbxproj',
      'macos/Runner/Configs/AppInfo.xcconfig',
      'linux/CMakeLists.txt',
    ], {
      identity.generatedAndroidApplicationId: identity.applicationId,
      identity.generatedAppleApplicationId: identity.applicationId,
    });

    await _patchAndroidMainActivity(projectRoot, identity);

    await _replacePattern(
      File(
        p.join(
          projectRoot.path,
          'android/app/src/main/AndroidManifest.xml',
        ),
      ),
      RegExp(r'android:label="[^"]*"'),
      'android:label="${identity.displayName}"',
    );

    await _setPlistDisplayName(
      File(p.join(projectRoot.path, 'ios/Runner/Info.plist')),
      identity.displayName,
    );
    await _setPlistDisplayName(
      File(p.join(projectRoot.path, 'macos/Runner/Info.plist')),
      identity.displayName,
    );

    await _patchWeb(projectRoot, identity);
    await _patchDesktopTitles(projectRoot, identity);
  }

  Future<void> _replaceInFiles(
    Directory root,
    List<String> relativePaths,
    Map<String, String> replacements,
  ) async {
    for (final relativePath in relativePaths) {
      final file = File(p.join(root.path, relativePath));
      if (!await file.exists()) continue;
      var content = await file.readAsString();
      for (final replacement in replacements.entries) {
        content = content.replaceAll(replacement.key, replacement.value);
      }
      await file.writeAsString(content);
    }
  }

  Future<void> _replacePattern(
    File file,
    Pattern pattern,
    String replacement,
  ) async {
    if (!await file.exists()) return;
    final content = await file.readAsString();
    await file.writeAsString(content.replaceFirst(pattern, replacement));
  }

  Future<void> _setPlistDisplayName(File file, String displayName) async {
    if (!await file.exists()) return;
    var content = await file.readAsString();
    final displayPattern = RegExp(
      r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>',
    );
    final entry =
        '<key>CFBundleDisplayName</key>\n\t<string>$displayName</string>';
    if (displayPattern.hasMatch(content)) {
      content = content.replaceFirst(displayPattern, entry);
    } else {
      content = content.replaceFirst('</dict>', '\t$entry\n</dict>');
    }
    await file.writeAsString(content);
  }

  Future<void> _patchWeb(Directory root, AppIdentity identity) async {
    final manifest = File(p.join(root.path, 'web/manifest.json'));
    if (await manifest.exists()) {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is Map<String, dynamic>) {
        decoded['name'] = identity.displayName;
        decoded['short_name'] = identity.displayName;
        await manifest.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
        );
      }
    }

    final index = File(p.join(root.path, 'web/index.html'));
    if (await index.exists()) {
      var content = await index.readAsString();
      content = content.replaceFirst(
        RegExp(r'<title>[^<]*</title>'),
        '<title>${identity.displayName}</title>',
      );
      content = content.replaceFirst(
        RegExp(
          r'<meta name="apple-mobile-web-app-title" content="[^"]*">',
        ),
        '<meta name="apple-mobile-web-app-title" '
        'content="${identity.displayName}">',
      );
      await index.writeAsString(content);
    }
  }

  Future<void> _patchDesktopTitles(
    Directory root,
    AppIdentity identity,
  ) async {
    await _replaceInFiles(root, [
      'linux/runner/my_application.cc',
      'windows/runner/main.cpp',
      'windows/runner/Runner.rc',
    ], {
      '"${identity.projectName}"': '"${identity.displayName}"',
      'L"${identity.projectName}"': 'L"${identity.displayName}"',
    });
  }

  Future<void> _patchAndroidMainActivity(
    Directory root,
    AppIdentity identity,
  ) async {
    for (final language in const ['kotlin', 'java']) {
      final sourceRoot = Directory(
        p.join(root.path, 'android/app/src/main', language),
      );
      if (!await sourceRoot.exists()) continue;
      await for (final entity in sourceRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            (p.basename(entity.path) != 'MainActivity.kt' &&
                p.basename(entity.path) != 'MainActivity.java')) {
          continue;
        }
        final isJava = p.extension(entity.path) == '.java';
        final content = (await entity.readAsString()).replaceFirst(
          RegExp(r'^package\s+[A-Za-z0-9_.]+;?', multiLine: true),
          'package ${identity.applicationId}${isJava ? ';' : ''}',
        );
        final destination = File(
          p.joinAll([
            sourceRoot.path,
            ...identity.applicationId.split('.'),
            p.basename(entity.path),
          ]),
        );
        await destination.parent.create(recursive: true);
        await destination.writeAsString(content);
        if (!p.equals(entity.path, destination.path)) {
          await entity.delete();
        }
        return;
      }
    }
  }
}
