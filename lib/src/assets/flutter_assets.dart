import 'dart:io';

import 'package:kareki/src/assets/flutter_colors.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A bundled logical asset or font family. Resolution variants and font faces
/// are retained together, because Flutter selects them at runtime.
class FlutterAsset {
  FlutterAsset(
    this.packageName,
    this.pubspecPath,
    this.name,
    this.node, {
    this.font = false,
    this.fontFiles = const {},
    this.color,
  });

  final String packageName;
  final String pubspecPath;
  final String name;
  final YamlNode node;
  final bool font;
  final Set<String> fontFiles;
  final FlutterColor? color;

  String get kind => color != null
      ? 'color'
      : font
      ? 'font'
      : 'asset';
  String get definitionPath => color?.path ?? pubspecPath;
  int get line => color?.line ?? node.span.start.line + 1;
  int get column => color?.column ?? node.span.start.column + 1;
  int get length => color?.length ?? node.span.length;

  String get id => '$packageName|$kind:$name';

  static List<FlutterAsset> load(String root, String packageName) {
    final file = File(p.join(root, 'pubspec.yaml'));
    final document = loadYamlNode(file.readAsStringSync(), sourceUrl: file.uri);
    if (document is! YamlMap) return [];
    final result = <String, FlutterAsset>{};
    for (final color in FlutterColor.load(root, document)) {
      final asset = FlutterAsset(
        packageName,
        file.path,
        color.name,
        document,
        color: color,
      );
      result[asset.id] = asset;
    }
    final flutter = document.nodes['flutter'];
    if (flutter is! YamlMap) return result.values.toList();
    void add(
      String name,
      YamlNode node, {
      bool font = false,
      Set<String> fontFiles = const {},
    }) {
      final asset = FlutterAsset(
        packageName,
        file.path,
        name,
        node,
        font: font,
        fontFiles: fontFiles,
      );
      result[asset.id] = asset;
    }

    final assets = flutter.nodes['assets'];
    if (assets != null && assets is! YamlList) {
      throw FormatException('${file.path}: flutter.assets must be a list.');
    }
    if (assets is YamlList) {
      for (final entry in assets.nodes) {
        final node = entry is YamlMap ? entry.nodes['path'] : entry;
        if (node is! YamlScalar || node.value is! String) {
          throw FormatException('${file.path}: asset path must be a string.');
        }
        final name = node.value as String;
        // Dependency assets are owned and reported by their declaring package.
        if (name.startsWith('packages/')) continue;
        final absolute = p.normalize(p.join(root, name));
        if (!p.isWithin(root, absolute)) {
          throw FormatException(
            '${file.path}: asset path escapes package: $name',
          );
        }
        if (!name.endsWith('/')) {
          add(p.posix.normalize(name), node);
          continue;
        }
        final directory = Directory(absolute);
        if (!directory.existsSync()) {
          throw FileSystemException('Asset directory is missing', absolute);
        }
        for (final child in directory.listSync(followLinks: false)) {
          if (child is File) {
            add(p.posix.join(name, p.basename(child.path)), node);
          } else if (child is Directory &&
              RegExp(r'^\d+(?:\.\d+)?x$').hasMatch(p.basename(child.path))) {
            // A main image need not exist; the lowest density variant then
            // supplies the fallback. Report its logical key only once.
            for (final variant
                in child.listSync(followLinks: false).whereType<File>()) {
              add(p.posix.join(name, p.basename(variant.path)), node);
            }
          }
        }
      }
    }
    final fonts = flutter.nodes['fonts'];
    if (fonts != null && fonts is! YamlList) {
      throw FormatException('${file.path}: flutter.fonts must be a list.');
    }
    if (fonts is YamlList) {
      for (final entry in fonts.nodes) {
        final family = entry is YamlMap ? entry.nodes['family'] : null;
        if (family is! YamlScalar ||
            family.value is! String ||
            (family.value as String).isEmpty) {
          throw FormatException('${file.path}: font family must be a string.');
        }
        final faces = (entry as YamlMap).nodes['fonts'];
        if (faces is! YamlList || faces.nodes.isEmpty) {
          throw FormatException(
            '${file.path}: font family must contain a non-empty fonts list.',
          );
        }
        final paths = <String>{};
        for (final face in faces.nodes) {
          final asset = face is YamlMap ? face.nodes['asset'] : null;
          if (asset is! YamlScalar ||
              asset.value is! String ||
              (asset.value as String).isEmpty) {
            throw FormatException(
              '${file.path}: font asset path must be a non-empty string.',
            );
          }
          final name = asset.value as String;
          if (!name.startsWith('packages/') &&
              !p.isWithin(root, p.normalize(p.join(root, name)))) {
            throw FormatException(
              '${file.path}: font asset path escapes package: $name',
            );
          }
          paths.add(p.posix.normalize(name));
        }
        add(family.value as String, family, font: true, fontFiles: paths);
      }
    }
    return result.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }
}
