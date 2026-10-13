import 'dart:convert';
import 'dart:io';

import 'package:kareki/src/model/package_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Recognizes build.yaml builder references and installed auto-applied builders.
/// Each analyzed package is treated as a possible build root, without running
/// builders or inferring usage from executables alone.
class BuilderDependencies {
  Set<String> forPackage(PackageInfo package) {
    final used = <String>{};
    final configuration = _readYaml(
      File(p.join(package.rootPath, 'build.yaml')),
    );
    final targets = configuration?['targets'];
    final targetBuilders = <Map<String, Object?>>[];
    if (targets is YamlMap && targets.isNotEmpty) {
      for (final target in targets.values) {
        final builders = target is YamlMap ? target['builders'] : null;
        final settings = <String, Object?>{};
        if (builders is YamlMap) {
          for (final entry in builders.entries) {
            if (entry.key is! String) continue;
            final key = _usageKey(entry.key as String, package.name);
            settings[key] = entry.value;
            if (!_disabled(entry.value)) used.add(key.split(':').first);
          }
        }
        targetBuilders.add(settings);
      }
    } else {
      targetBuilders.add({});
    }

    final roots = _packageRoots(package.rootPath);
    for (final name in {...package.dependencies, ...package.devDependencies}) {
      final root = roots[name];
      if (root == null || root.scheme != 'file') continue;
      final config = _readYaml(File.fromUri(root.resolve('build.yaml')));
      final definitions = config?['builders'];
      if (definitions is! YamlMap) continue;
      for (final entry in definitions.entries) {
        if (entry.key is! String || entry.value is! YamlMap) continue;
        final definition = entry.value as YamlMap;
        if (!{
          'dependents',
          'all_packages',
          'root_package',
        }.contains(definition['auto_apply'])) {
          continue;
        }
        final rawKey = (entry.key as String).replaceFirst('|', ':');
        final key = rawKey.startsWith(':')
            ? '$name$rawKey'
            : rawKey.contains(':')
            ? rawKey
            : '$name:$rawKey';
        if (!key.startsWith('$name:')) continue;
        if (targetBuilders.any((settings) => !_disabled(settings[key]))) {
          used.add(name);
        }
      }
    }
    return used;
  }

  bool _disabled(Object? settings) =>
      settings is YamlMap && settings['enabled'] == false;

  String _usageKey(String key, String packageName) {
    final normalized = key.replaceFirst('|', ':');
    if (normalized.startsWith(':')) return '$packageName$normalized';
    return normalized.contains(':') ? normalized : '$normalized:$normalized';
  }

  YamlMap? _readYaml(File file) {
    if (!file.existsSync()) return null;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      return yaml is YamlMap ? yaml : null;
    } on YamlException {
      return null;
    }
  }

  Map<String, Uri> _packageRoots(String directory) {
    var current = directory;
    while (true) {
      final config = File(p.join(current, '.dart_tool', 'package_config.json'));
      if (config.existsSync()) {
        try {
          final json = jsonDecode(config.readAsStringSync());
          if (json is! Map || json['packages'] is! List) return {};
          return {
            for (final entry in json['packages'] as List)
              if (entry is Map &&
                  entry['name'] is String &&
                  entry['rootUri'] is String)
                entry['name'] as String: config.uri.resolve(
                  (entry['rootUri'] as String).endsWith('/')
                      ? entry['rootUri'] as String
                      : '${entry['rootUri']}/',
                ),
          };
        } on FormatException {
          return {};
        }
      }
      final parent = p.dirname(current);
      if (parent == current) return {};
      current = parent;
    }
  }
}
