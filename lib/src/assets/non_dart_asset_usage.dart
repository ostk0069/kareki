import 'dart:convert';
import 'dart:io';

import 'package:kareki/src/assets/flutter_assets.dart';
import 'package:path/path.dart' as p;

/// Literal resource paths used by build workflows, native configuration, and
/// scripts. Registrations and generated/cache files do not establish usage.
abstract final class NonDartAssetUsage {
  // Start at a token boundary: retrying a filename suffix at every character
  // makes long embedded SVG/base64 data take quadratic time.
  static final _pathToken = RegExp(
    r"""(?:^|[\s"'<>:=(){}\[\],;$])([^\s"'<>:=(){}\[\],;$]+\.[a-zA-Z0-9_-]+)""",
  );
  static final _quotedPath = RegExp(
    r"""["']([^"'$\r\n]+\.[a-zA-Z0-9_-]+)["']""",
  );
  static const _extensions = {
    '.yaml',
    '.yml',
    '.json',
    '.sh',
    '.xml',
    '.svg',
    '.html',
    '.js',
    '.ts',
    '.css',
    '.toml',
    '.gradle',
    '.swift',
    '.kt',
    '.java',
    '.m',
    '.mm',
    '.cc',
    '.cpp',
    '.c',
    '.h',
  };
  static const _configFiles = {
    'pubspec.yaml',
    'kareki-config.yaml',
    'kareki_config.yaml',
    'kareki.yaml',
  };
  static const _pruned = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.symlinks',
  };

  static Set<String> collect(String root, List<FlutterAsset> assets) {
    if (assets.isEmpty) return {};
    final workspacePaths = <String, Set<String>>{};
    final localPaths = <String, Map<String, Set<String>>>{};
    final absolutePaths = <String, Set<String>>{};
    for (final asset in assets) {
      if (asset.color != null) continue;
      final packageRoot = p.dirname(asset.pubspecPath);
      for (final path in asset.font ? asset.fontFiles : {asset.name}) {
        final absolute = p.normalize(p.join(packageRoot, path));
        absolutePaths.putIfAbsent(absolute, () => {}).add(asset.id);
        final relative = p.relative(absolute, from: root);
        workspacePaths
            .putIfAbsent(p.posix.normalize(relative), () => {})
            .add(asset.id);
        workspacePaths
            .putIfAbsent('packages/${asset.packageName}/$path', () => {})
            .add(asset.id);
        localPaths
            .putIfAbsent(packageRoot, () => {})
            .putIfAbsent(path, () => {})
            .add(asset.id);
      }
    }
    if (absolutePaths.isEmpty) return {};
    final used = <String>{};
    for (final file in _sources(Directory(root))) {
      final text = file.readAsStringSync();
      if (p.extension(file.path) == '.json' && _isReport(text)) {
        continue;
      }
      final references = {
        for (final match in _pathToken.allMatches(text)) match.group(1)!,
        for (final match in _quotedPath.allMatches(text)) match.group(1)!,
      };
      for (final reference in references) {
        final path = p.posix.normalize(reference);
        used.addAll(
          absolutePaths[p.normalize(p.join(p.dirname(file.path), path))] ??
              const {},
        );
        used.addAll(workspacePaths[path] ?? const {});
        for (final entry in localPaths.entries) {
          if (p.isWithin(entry.key, file.path)) {
            used.addAll(entry.value[path] ?? const {});
          }
        }
      }
    }
    return used;
  }

  static bool _isReport(String text) {
    if (!text.contains('"kareki"') || !text.contains('"findings"')) {
      return false;
    }
    try {
      final decoded = jsonDecode(text);
      return decoded is Map &&
          decoded['tool'] == 'kareki' &&
          decoded['findings'] is List;
    } on FormatException {
      return false;
    }
  }

  static Iterable<File> _sources(Directory directory) sync* {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (!_pruned.contains(p.basename(entity.path))) yield* _sources(entity);
      } else if (entity is File &&
          !_configFiles.contains(p.basename(entity.path)) &&
          _extensions.contains(p.extension(entity.path)) &&
          entity.lengthSync() <= 1024 * 1024) {
        yield entity;
      }
    }
  }
}
