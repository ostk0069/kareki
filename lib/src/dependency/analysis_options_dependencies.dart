import 'dart:convert';
import 'dart:io';

import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Dependencies can be used by analyzer configuration instead of Dart imports.
/// Follow the nearest options file for each source and recursive includes using
/// the owning package's configuration. Never execute configuration contents.
class AnalysisOptionsDependencies {
  Set<String> forPackage(PackageInfo package, Iterable<ParsedFile> files) {
    final used = <String>{};
    final roots = <String, Uri>{};
    final config = _nearest(package.rootPath, '.dart_tool/package_config.json');
    if (config != null) {
      try {
        final json = jsonDecode(config.readAsStringSync());
        if (json is Map && json['packages'] is List) {
          for (final entry in json['packages'] as List) {
            if (entry is! Map ||
                entry['name'] is! String ||
                entry['rootUri'] is! String) {
              continue;
            }
            final rawRoot = entry['rootUri'] as String;
            final root = config.uri.resolve(
              rawRoot.endsWith('/') ? rawRoot : '$rawRoot/',
            );
            roots[entry['name'] as String] = root.resolve(
              entry['packageUri'] is String
                  ? entry['packageUri'] as String
                  : '',
            );
          }
        }
      } on FormatException {
        // Direct package includes still establish use without a valid config.
      }
    }
    final visited = <String>{};
    void read(File file) {
      if (!file.existsSync() || !visited.add(file.resolveSymbolicLinksSync())) {
        return;
      }
      Object? yaml;
      try {
        yaml = loadYaml(file.readAsStringSync());
      } on YamlException {
        return;
      }
      if (yaml is! YamlMap) return;
      final include = yaml['include'];
      for (final value in include is List ? include : [include]) {
        if (value is! String) continue;
        final uri = Uri.tryParse(value);
        if (uri == null) continue;
        Uri? target;
        if (uri.scheme == 'package' && uri.pathSegments.length >= 2) {
          final name = uri.pathSegments.first;
          used.add(name);
          target = roots[name]?.resolve(uri.pathSegments.skip(1).join('/'));
        } else if (!uri.hasScheme) {
          target = file.uri.resolveUri(uri);
        }
        if (target?.scheme == 'file') read(File.fromUri(target!));
      }
    }

    for (final directory in {
      package.rootPath,
      ...files.map((file) => p.dirname(file.path)),
    }) {
      final options = _nearest(directory, 'analysis_options.yaml');
      if (options != null) read(options);
    }
    return used;
  }

  File? _nearest(String directory, String name) {
    var current = directory;
    while (true) {
      final file = File(p.join(current, name));
      if (file.existsSync()) return file;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }
}
