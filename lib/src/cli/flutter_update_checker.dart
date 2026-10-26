import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

enum UpdateStatus { available, current, ahead, diverged, unknown, unavailable }

final class UpdateResult {
  const UpdateResult(this.status, {this.installed, this.latest});

  final UpdateStatus status;
  final String? installed;
  final String? latest;
}

typedef RevisionReader = Future<String?> Function();
typedef JsonReader = Future<Object?> Function(Uri uri);

final class FlutterUpdateChecker {
  FlutterUpdateChecker({
    RevisionReader? revisionReader,
    JsonReader? jsonReader,
    this.timeout = const Duration(milliseconds: 1800),
  })  : _revisionReader = revisionReader ?? readInstalledRevision,
        _jsonReader = jsonReader;

  static const repository = 'crisantus/gold-flutter';
  static final _revision = RegExp(r'^[0-9a-f]{40}$');
  final RevisionReader _revisionReader;
  final JsonReader? _jsonReader;
  final Duration timeout;

  /// One deadline covers revision lookup, both requests, and response bodies.
  /// Closing the client also cancels an outstanding request after a timeout.
  Future<UpdateResult> check() async {
    final client = HttpClient();
    try {
      return await _check(_jsonReader ?? (uri) => _readJson(client, uri))
          .timeout(timeout);
    } on Exception {
      return const UpdateResult(UpdateStatus.unavailable);
    } finally {
      client.close(force: true);
    }
  }

  Future<UpdateResult> _check(JsonReader read) async {
    final installed = await _revisionReader();
    if (installed == null || !_revision.hasMatch(installed)) {
      return const UpdateResult(UpdateStatus.unknown);
    }
    const api = 'https://api.github.com/repos/$repository';
    final reference = await read(Uri.parse('$api/git/ref/heads/main'));
    final object = reference is Map ? reference['object'] : null;
    final latest = object is Map ? object['sha'] : null;
    if (latest is! String || !_revision.hasMatch(latest)) {
      return const UpdateResult(UpdateStatus.unavailable);
    }
    if (installed == latest) {
      return UpdateResult(UpdateStatus.current,
          installed: installed, latest: latest);
    }
    final comparison = await read(
      Uri.parse('$api/compare/$installed...$latest?per_page=1'),
    );
    final status = switch (comparison is Map ? comparison['status'] : null) {
      'ahead' => UpdateStatus.available,
      'behind' => UpdateStatus.ahead,
      'identical' => UpdateStatus.current,
      'diverged' => UpdateStatus.diverged,
      _ => UpdateStatus.unavailable,
    };
    return UpdateResult(status, installed: installed, latest: latest);
  }

  static Future<Object?> _readJson(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'gold-flutter-update-check');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('GitHub update check failed.');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('GitHub response is too large.');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  /// Resolve this package, never the generated app in the working directory.
  /// Pub's Git checkouts use a detached HEAD, so no Git subprocess is needed.
  static Future<String?> readInstalledRevision() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:gold_flutter/gold_flutter.dart'),
    );
    if (uri == null || uri.scheme != 'file') return null;
    final root = p.dirname(p.dirname(uri.toFilePath()));
    var gitDirectory = p.join(root, '.git');
    final gitFile = File(gitDirectory);
    if (await gitFile.exists()) {
      final pointer = (await gitFile.readAsString()).trim();
      if (!pointer.startsWith('gitdir: ')) return null;
      gitDirectory = p.normalize(p.join(root, pointer.substring(8)));
    }
    final headFile = File(p.join(gitDirectory, 'HEAD'));
    if (!await headFile.exists()) return null;
    final head = (await headFile.readAsString()).trim();
    if (_revision.hasMatch(head)) return head;
    if (!head.startsWith('ref: refs/')) return null;
    final ref = head.substring(5);
    if (!RegExp(r'^refs/[a-zA-Z0-9_./-]+$').hasMatch(ref) ||
        ref.split('/').contains('..')) {
      return null;
    }
    final refFile = File(p.join(gitDirectory, ref));
    if (await refFile.exists()) {
      final value = (await refFile.readAsString()).trim();
      return _revision.hasMatch(value) ? value : null;
    }
    final packed = File(p.join(gitDirectory, 'packed-refs'));
    if (!await packed.exists()) return null;
    for (final line in await packed.readAsLines()) {
      final parts = line.split(' ');
      if (parts.length == 2 &&
          parts[1] == ref &&
          _revision.hasMatch(parts[0])) {
        return parts[0];
      }
    }
    return null;
  }
}
