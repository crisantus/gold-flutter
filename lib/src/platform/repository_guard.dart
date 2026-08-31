import 'dart:io';

abstract interface class GitExecutor {
  Future<String> topLevelFor(Directory workingDirectory);

  Future<String> originFor(Directory workingDirectory);
}

final class ProcessGitExecutor implements GitExecutor {
  const ProcessGitExecutor();

  @override
  Future<String> topLevelFor(Directory workingDirectory) async {
    return _runGit(workingDirectory, const ['rev-parse', '--show-toplevel']);
  }

  @override
  Future<String> originFor(Directory workingDirectory) async {
    return _runGit(
      workingDirectory,
      const ['remote', 'get-url', 'origin'],
    );
  }

  Future<String> _runGit(
    Directory workingDirectory,
    List<String> arguments,
  ) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: workingDirectory.path,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw RepositoryIsolationException(
        result.stderr.toString().trim().isEmpty
            ? 'Unable to verify the Git repository.'
            : result.stderr.toString().trim(),
      );
    }
    return result.stdout.toString().trim();
  }
}

final class GitRemoteIdentity {
  const GitRemoteIdentity(this.slug);

  final String slug;

  static GitRemoteIdentity parse(String remote) {
    final trimmed = remote.trim().replaceFirst(RegExp(r'\.git$'), '');
    final match = RegExp(
      r'^(?:git@github\.com:|https://github\.com/)([^/]+/[^/]+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match == null) {
      throw const RepositoryIsolationException(
        'Origin is not a recognized GitHub repository.',
      );
    }

    return GitRemoteIdentity(match.group(1)!.toLowerCase());
  }
}

final class RepositoryIsolationException implements Exception {
  const RepositoryIsolationException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class RepositoryGuard {
  const RepositoryGuard({required GitExecutor executor}) : _executor = executor;

  final GitExecutor _executor;

  Future<void> verify({
    required Directory workingDirectory,
    required String expectedRepositorySlug,
  }) async {
    final expectedRoot = workingDirectory.absolute.path;
    final actualRoot = Directory(
      await _executor.topLevelFor(workingDirectory),
    ).absolute.path;
    final actualOrigin = await _executor.originFor(workingDirectory);
    final actualSlug = GitRemoteIdentity.parse(actualOrigin).slug;

    if (actualRoot != expectedRoot ||
        actualSlug != expectedRepositorySlug.toLowerCase()) {
      throw const RepositoryIsolationException(
        'Refusing Git operation outside the approved gold-flutter repository.',
      );
    }
  }
}
