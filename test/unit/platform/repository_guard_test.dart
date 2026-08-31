import 'dart:io';

import 'package:gold_flutter/src/platform/repository_guard.dart';
import 'package:test/test.dart';

void main() {
  group('RepositoryGuard', () {
    test('accepts the exact repository root and GitHub origin', () async {
      final guard = RepositoryGuard(
        executor: _FakeGitExecutor(
          topLevel: '/work/gold-flutter',
          origin: 'git@github.com:owner/gold-flutter.git',
        ),
      );

      await expectLater(
        guard.verify(
          workingDirectory: Directory('/work/gold-flutter'),
          expectedRepositorySlug: 'owner/gold-flutter',
        ),
        completes,
      );
    });

    test('accepts an HTTPS GitHub origin', () async {
      final guard = RepositoryGuard(
        executor: _FakeGitExecutor(
          topLevel: '/work/gold-flutter',
          origin: 'https://github.com/owner/gold-flutter.git',
        ),
      );

      await expectLater(
        guard.verify(
          workingDirectory: Directory('/work/gold-flutter'),
          expectedRepositorySlug: 'owner/gold-flutter',
        ),
        completes,
      );
    });

    test('rejects a different repository root', () async {
      final guard = RepositoryGuard(
        executor: _FakeGitExecutor(
          topLevel: '/work/parkclock',
          origin: 'git@github.com:owner/gold-flutter.git',
        ),
      );

      await expectLater(
        guard.verify(
          workingDirectory: Directory('/work/gold-flutter'),
          expectedRepositorySlug: 'owner/gold-flutter',
        ),
        throwsA(isA<RepositoryIsolationException>()),
      );
    });

    test('rejects a different GitHub origin', () async {
      final guard = RepositoryGuard(
        executor: _FakeGitExecutor(
          topLevel: '/work/gold-flutter',
          origin: 'https://github.com/owner/another-repository.git',
        ),
      );

      await expectLater(
        guard.verify(
          workingDirectory: Directory('/work/gold-flutter'),
          expectedRepositorySlug: 'owner/gold-flutter',
        ),
        throwsA(isA<RepositoryIsolationException>()),
      );
    });
  });
}

final class _FakeGitExecutor implements GitExecutor {
  const _FakeGitExecutor({required this.topLevel, required this.origin});

  final String topLevel;
  final String origin;

  @override
  Future<String> originFor(Directory workingDirectory) async => origin;

  @override
  Future<String> topLevelFor(Directory workingDirectory) async => topLevel;
}
