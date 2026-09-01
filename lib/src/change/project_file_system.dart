import 'dart:io';

abstract interface class ProjectFileSystem {
  Future<String> createTemporaryDirectory(String prefix);
  Future<bool> exists(String path);
  Future<bool> isLink(String path);
  Future<bool> containsLink(String path);
  Future<List<int>> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> delete(String path);
  Future<bool> deleteEmptyDirectory(String path);
  Future<void> copyTree(String source, String destination);
}

final class LocalProjectFileSystem implements ProjectFileSystem {
  const LocalProjectFileSystem();

  static int _temporaryFileSequence = 0;

  @override
  Future<String> createTemporaryDirectory(String prefix) async =>
      (await Directory.systemTemp.createTemp(prefix)).path;

  @override
  Future<bool> exists(String path) => FileSystemEntity.type(path).then(
        (type) => type != FileSystemEntityType.notFound,
      );

  @override
  Future<bool> isLink(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.link;

  @override
  Future<bool> containsLink(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      return true;
    }
    if (type != FileSystemEntityType.directory) {
      return false;
    }
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (await containsLink(entity.path)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final sequence = _temporaryFileSequence++;
    final temporary = File(
      '$path.gold-txn-$pid-${DateTime.now().microsecondsSinceEpoch}-'
      '$sequence.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> delete(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.notFound:
        return;
      default:
        throw FileSystemException('Unsupported file-system entity', path);
    }
  }

  @override
  Future<bool> deleteEmptyDirectory(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      return false;
    }
    try {
      await Directory(path).delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> copyTree(String source, String destination) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        final target = File(destination);
        await target.parent.create(recursive: true);
        await File(source).copy(destination);
      case FileSystemEntityType.directory:
        final target = Directory(destination);
        await target.create(recursive: true);
        await for (final entity in Directory(source).list(followLinks: false)) {
          final name = entity.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
          );
          await copyTree(
            entity.path,
            '${target.path}${Platform.pathSeparator}$name',
          );
        }
      case FileSystemEntityType.link:
        final target = Link(destination);
        await target.parent.create(recursive: true);
        await target.create(await Link(source).target());
      case FileSystemEntityType.notFound:
        throw FileSystemException('Snapshot source does not exist', source);
      default:
        throw FileSystemException('Unsupported file-system entity', source);
    }
  }
}
