import 'dart:convert';
import 'dart:io';

import 'package:kareki/src/model/package_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Native plugins can be used through Flutter's build/registration pipeline
/// without any Dart import. Resolve their installed metadata, including path,
/// git and hosted dependencies, from the owning package's pub configuration.
/// Caches are scoped to one analysis, never shared across source snapshots.
class NativePluginDependencies {
  final _configurations = <String, Map<String, Uri>>{};
  final _plugins = <(String, String), bool>{};

  Set<String> forPackage(PackageInfo package, {required bool strict}) {
    var directory = package.rootPath;
    while (true) {
      final config = File(
        p.join(directory, '.dart_tool', 'package_config.json'),
      );
      if (config.existsSync()) {
        final roots = _configurations.putIfAbsent(
          config.path,
          () => _readConfiguration(config),
        );
        return {
          for (final name in {
            ...package.dependencies,
            if (strict) ...package.devDependencies,
          })
            if (roots[name] case final root?)
              if (_plugins.putIfAbsent((
                name,
                root.toString(),
              ), () => _isNativePlugin(name, root)))
                name,
        };
      }
      final parent = p.dirname(directory);
      if (parent == directory) return {};
      directory = parent;
    }
  }

  Map<String, Uri> _readConfiguration(File file) {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map || json['packages'] is! List) return {};
      return {
        for (final entry in json['packages'] as List)
          if (entry is Map &&
              entry['name'] is String &&
              entry['rootUri'] is String)
            entry['name'] as String: file.uri.resolve(
              entry['rootUri'] as String,
            ),
      };
    } on FormatException {
      return {};
    }
  }

  bool _isNativePlugin(String name, Uri root) {
    if (root.scheme != 'file') return false;
    try {
      final file = File(p.join(root.toFilePath(), 'pubspec.yaml'));
      if (!file.existsSync()) return false;
      final yaml = loadYaml(file.readAsStringSync());
      if (yaml is! YamlMap || yaml['name'] != name) return false;
      final flutter = yaml['flutter'];
      if (flutter is! YamlMap) return false;
      final plugin = flutter['plugin'];
      if (plugin is! YamlMap) return false;
      bool hasNativeEntry(Object? value) =>
          value is YamlMap &&
          (value['ffiPlugin'] == true ||
              (value['pluginClass'] is String &&
                  (value['pluginClass'] as String).isNotEmpty));
      final platforms = plugin['platforms'];
      return hasNativeEntry(plugin) ||
          (platforms is YamlMap && platforms.values.any(hasNativeEntry));
    } on YamlException {
      return false;
    }
  }
}
