import 'package:path/path.dart' as p;

/// Metadata about a discovered pub package within a workspace.
class PackageInfo {
  PackageInfo({
    required this.name,
    required this.rootPath,
    required this.pubspecPath,
    required this.dependencies,
    required this.devDependencies,
  });

  /// Package name from `pubspec.yaml`.
  final String name;

  /// Absolute path to the package root (directory containing `pubspec.yaml`).
  final String rootPath;

  /// Absolute path to the package's `pubspec.yaml`.
  final String pubspecPath;

  /// Direct dependency names from the `dependencies:` section.
  final Set<String> dependencies;

  /// Direct dev dependency names from the `dev_dependencies:` section.
  final Set<String> devDependencies;

  /// Absolute path to the package's `lib/` directory.
  String get libPath => p.join(rootPath, 'lib');

  /// Absolute path to the package's `test/` directory.
  String get testPath => p.join(rootPath, 'test');

  /// Absolute path to the package's `bin/` directory.
  String get binPath => p.join(rootPath, 'bin');
}
