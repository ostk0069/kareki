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
    'hook',
  ]) {
    final dir = Directory(p.join(packageRoot, sub));
    if (dir.existsSync()) yield* _filesBelow(dir, '.dart');
  }
}

/// ARB files are also valid exclude.files subjects for localization checks.
Iterable<File> packageArbFiles(String packageRoot) =>
    _filesBelow(Directory(packageRoot), '.arb', isPackageRoot: true);

Iterable<File> _filesBelow(
  Directory directory,
  String extension, {
  bool isPackageRoot = false,
}) sync* {
  // A child pubspec establishes ownership even when the child isn't listed
  // in the workspace. Registered children are scanned separately.
  if (!isPackageRoot &&
      File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
    return;
  }
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is File && entity.path.endsWith(extension)) {
      yield entity;
    } else if (entity is Directory) {
      // Prune before descending, including large build/cache directories.
      if ({'.dart_tool', '.git', 'build'}.contains(p.basename(entity.path))) {
        continue;
      }
      yield* _filesBelow(entity, extension);
    }
  }
}
