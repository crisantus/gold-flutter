import 'dart:io';

import 'package:path/path.dart' as p;

final class DestinationExistsException implements Exception {
  const DestinationExistsException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class StagingArea {
  StagingArea._({required this.directory, required this.destination});

  final Directory directory;
  final Directory destination;
  bool _published = false;

  static Future<StagingArea> create({required Directory destination}) async {
    final normalizedDestination = Directory(
      p.normalize(p.absolute(destination.path)),
    );
    final parent = normalizedDestination.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (await normalizedDestination.exists() &&
        !await _isDirectoryEmpty(normalizedDestination)) {
      throw DestinationExistsException(
        'Refusing to overwrite non-empty destination: '
        '${normalizedDestination.path}',
      );
    }

    final safeName = p
        .basename(normalizedDestination.path)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    var counter = 0;
    late Directory staging;
    do {
      staging = Directory(
        p.join(
          parent.path,
          '.gold_flutter_${safeName}_${pid}_${counter++}',
        ),
      );
    } while (await staging.exists());
    await staging.create();

    return StagingArea._(
      directory: staging,
      destination: normalizedDestination,
    );
  }

  Future<void> publish() async {
    if (_published) return;
    if (!await directory.exists()) {
      throw StateError('The generator staging directory no longer exists.');
    }
    if (await destination.exists()) {
      if (!await _isDirectoryEmpty(destination)) {
        throw DestinationExistsException(
          'Refusing to overwrite non-empty destination: ${destination.path}',
        );
      }
      await destination.delete();
    }
    await directory.rename(destination.path);
    _published = true;
  }

  Future<void> dispose() async {
    if (_published || !await directory.exists()) return;
    final isOwnedName = p.basename(directory.path).startsWith('.gold_flutter_');
    final hasExpectedParent = p.equals(
      directory.parent.path,
      destination.parent.path,
    );
    if (!isOwnedName || !hasExpectedParent) {
      throw StateError('Refusing to remove an unowned staging directory.');
    }
    await directory.delete(recursive: true);
  }

  static Future<bool> _isDirectoryEmpty(Directory directory) async {
    await for (final _ in directory.list(followLinks: false)) {
      return false;
    }
    return true;
  }
}
