import 'dart:convert';
import 'dart:io';

import 'package:gold_flutter/src/change/project_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('atomically replaces through a sibling temp without leaving artifacts',
      () async {
    final root = await Directory.systemTemp.createTemp('gold_atomic_write_');
    addTearDown(() => root.delete(recursive: true));
    final target = File(p.join(root.path, 'target.txt'));
    await target.writeAsString('old');
    RandomAccessFile? originalHandle;
    if (!Platform.isWindows) {
      originalHandle = await target.open(mode: FileMode.read);
      addTearDown(originalHandle.close);
    }

    await const LocalProjectFileSystem().writeBytes(
      target.path,
      utf8.encode('new'),
    );

    expect(target.readAsStringSync(), 'new');
    if (originalHandle != null) {
      await originalHandle.setPosition(0);
      expect(utf8.decode(await originalHandle.read(3)), 'old');
    }
    expect(
      root.listSync().map((entity) => p.basename(entity.path)),
      ['target.txt'],
    );
  });
}
