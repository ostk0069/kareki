import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Loads workspace packages from `melos.yaml` or a pub workspace
/// (`pubspec.yaml` with a `workspace:` section), falling back to a single
/// root package when neither is present.
class WorkspaceLoader {
  WorkspaceLoader({required this.rootPath});

  /// Absolute path to the workspace root.
  final String rootPath;

  /// Resolve the list of packages in the workspace.
  ///
  /// Resolution order:
  /// 1. `melos.yaml` with `packages:` and optional `ignore:` globs
  /// 2. `pubspec.yaml` with a `workspace:` list (Dart 3.6+ pub workspaces)
  /// 3. The root directory as a single package
  ///
  /// Globs from `[include]` and `[exclude]` (if non-empty) override the
  /// default resolution.
  List<PackageInfo> load({
    List<String> include = const [],
    List<String> exclude = const [],
  }) {
    final globs = _resolveGlobs(include: include, exclude: exclude);
    final dirs = _expandGlobs(globs.include, globs.exclude);
    return dirs
        .map(_loadPackage)
        .where((pkg) => pkg != null)
        .cast<PackageInfo>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  ({List<String> include, List<String> exclude}) _resolveGlobs({
    required List<String> include,
    required List<String> exclude,
  }) {
    if (include.isNotEmpty) {
      return (include: include, exclude: exclude);
    }

    final melosFile = File(p.join(rootPath, 'melos.yaml'));
    if (melosFile.existsSync()) {
      final yaml = loadYaml(melosFile.readAsStringSync());
      if (yaml is YamlMap) {
        final packages =
            (yaml['packages'] as YamlList?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        final ignore =
            (yaml['ignore'] as YamlList?)?.map((e) => e.toString()).toList() ??
            const <String>[];
        if (packages.isNotEmpty) {
          return (include: packages, exclude: [...ignore, ...exclude]);
        }
      }
    }

    final rootPubspec = File(p.join(rootPath, 'pubspec.yaml'));
    if (rootPubspec.existsSync()) {
      final yaml = loadYaml(rootPubspec.readAsStringSync());
      if (yaml is YamlMap) {
        final workspace =
            (yaml['workspace'] as YamlList?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        if (workspace.isNotEmpty) {
          return (include: ['.', ...workspace], exclude: exclude);
        }
      }
    }

    return (include: ['.'], exclude: exclude);
  }

  List<String> _expandGlobs(List<String> include, List<String> exclude) {
    final excludeGlobs = exclude.map(_toGlob).toList();
    final hits = <String>{};

    for (final pattern in include) {
      if (pattern == '.') {
        if (File(p.join(rootPath, 'pubspec.yaml')).existsSync()) {
          hits.add(rootPath);
        }
        continue;
      }

      final glob = _toGlob(pattern);
      for (final entity in glob.listSync(root: rootPath, followLinks: false)) {
        if (entity is! Directory) continue;
        final abs = p.normalize(entity.absolute.path);
        if (!File(p.join(abs, 'pubspec.yaml')).existsSync()) continue;
        final rel = p.relative(abs, from: rootPath);
        if (excludeGlobs.any((g) => g.matches(rel))) continue;
        hits.add(abs);
      }
    }

    return hits.toList();
  }

  Glob _toGlob(String pattern) => Glob(pattern, recursive: true);

  PackageInfo? _loadPackage(String dir) {
    final pubspecPath = p.join(dir, 'pubspec.yaml');
    final file = File(pubspecPath);
    if (!file.existsSync()) return null;
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) return null;
    final name = yaml['name']?.toString();
    if (name == null) return null;
    return PackageInfo(
      name: name,
      rootPath: dir,
      pubspecPath: pubspecPath,
      dependencies: _depNames(yaml['dependencies']),
      devDependencies: _depNames(yaml['dev_dependencies']),
    );
  }

  Set<String> _depNames(Object? section) {
    if (section is! YamlMap) return const {};
    return section.keys.map((k) => k.toString()).toSet();
  }
}
