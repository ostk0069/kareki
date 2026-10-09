import 'dart:io';

import 'package:path/path.dart' as p;

/// Shared source scope for analysis and doctor suppression checks.
Iterable<File> packageDartFiles(String packageRoot) sync* {
  // Tooling packages can put scripts directly beside pubspec.yaml.
  yield* Directory(packageRoot)
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final sub in [
    'lib',
    'bin',
    'test',
    'integration_test',
    'example',
    'tool',
    'tools',
  ]) {
    final dir = Directory(p.join(packageRoot, sub));
    if (dir.existsSync()) yield* _dartFilesBelow(dir);
  }
}

Iterable<File> _dartFilesBelow(Directory directory) sync* {
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    } else if (entity is Directory) {
      // Prune before descending, including large build/cache directories.
      if ({'.dart_tool', '.git', 'build'}.contains(p.basename(entity.path))) {
        continue;
      }
      yield* _dartFilesBelow(entity);
    }
  }
}
