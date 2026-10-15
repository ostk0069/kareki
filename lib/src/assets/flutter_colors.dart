import 'dart:io';

import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';
import 'package:yaml/yaml.dart';

/// A source color may generate both a material and an accent member.
class FlutterColor {
  FlutterColor(
    this.name,
    this.members,
    this.path,
    this.offset,
    this.length,
    this.line,
    this.column,
    this.outputPath,
    this.className,
  );

  final String name;
  final Set<String> members;
  final String path;
  final int offset;
  final int length;
  final int line;
  final int column;
  final String outputPath;
  final String className;

  static List<FlutterColor> load(String root, YamlMap document) {
    var config = <Object?, Object?>{};
    final declared = document['flutter_gen'];
    if (declared is Map) config.addAll(declared);
    final build = File(p.join(root, 'build.yaml'));
    if (build.existsSync()) {
      var configuredTarget = false;
      final data = loadYaml(build.readAsStringSync());
      if (data is Map && data['targets'] is Map) {
        for (final target in (data['targets'] as Map).values) {
          if (target is! Map || target['builders'] is! Map) continue;
          for (final entry in (target['builders'] as Map).entries) {
            if (!{
              'flutter_gen',
              'flutter_gen_runner',
              'flutter_gen_runner:flutter_gen_runner',
              'flutter_gen:flutter_gen',
            }.contains(entry.key)) {
              continue;
            }
            final builder = entry.value;
            if (builder is Map && builder['options'] is Map) {
              if (configuredTarget) {
                throw const FormatException(
                  'Multiple FlutterGen builder options are ambiguous; use one configured target.',
                );
              }
              configuredTarget = true;
              config = _merge(config, builder['options'] as Map);
            }
          }
        }
      }
    }
    final colors = config['colors'];
    if (colors == null) return [];
    if (colors is! Map) {
      throw const FormatException('flutter_gen.colors must be a map.');
    }
    if (colors['enabled'] != null && colors['enabled'] is! bool) {
      throw const FormatException(
        'flutter_gen.colors.enabled must be a boolean.',
      );
    }
    if (colors['enabled'] == false) return [];
    final inputs = colors['inputs'];
    if (inputs == null) return [];
    if (inputs is! List) {
      throw const FormatException('flutter_gen.colors.inputs must be a list.');
    }
    final outputs = colors['outputs'];
    if (outputs != null && outputs is! Map) {
      throw const FormatException('flutter_gen.colors.outputs must be a map.');
    }
    final className = outputs is Map
        ? outputs['class_name'] ?? 'ColorName'
        : 'ColorName';
    final output = config['output'] ?? 'lib/gen/';
    if (className is! String || output is! String) {
      throw const FormatException(
        'FlutterGen color class and output must be strings.',
      );
    }
    final outputPath = p.normalize(p.join(root, output, 'colors.gen.dart'));
    if (!p.isWithin(root, outputPath)) {
      throw const FormatException('FlutterGen color output escapes package.');
    }
    final result = <String, FlutterColor>{};
    for (final input in inputs.toSet()) {
      if (input is! String || p.extension(input) != '.xml') {
        throw const FormatException(
          'FlutterGen color input must be an XML path.',
        );
      }
      final path = p.normalize(p.join(root, input));
      if (!p.isWithin(root, path)) {
        throw const FormatException('FlutterGen color input escapes package.');
      }
      final content = File(path).readAsStringSync();
      final xml = XmlDocument.parse(content);
      final starts = parseEvents(content, withLocation: true)
          .whereType<XmlStartElementEvent>()
          .where((e) => e.name == 'color')
          .toList();
      final lines = LineInfo.fromContent(content);
      var index = 0;
      for (final element in xml.findAllElements('color')) {
        final start = starts[index++];
        final name = element.getAttribute('name');
        if (name == null ||
            name.isEmpty ||
            !RegExp(
              r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$',
            ).hasMatch(element.innerText.trim())) {
          throw FormatException('$path: Invalid FlutterGen color definition.');
        }
        // FlutterGen keeps the first definition for a duplicated name.
        if (result.containsKey(name)) continue;
        final member = _camelCase(name);
        final types = element.getAttribute('type')?.split(' ') ?? <String>[];
        final members = {
          if (types.isEmpty || types.contains('material')) member,
          if (types.contains('material-accent')) '${member}Accent',
        };
        if (members.isEmpty ||
            !RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$').hasMatch(member)) {
          throw FormatException(
            '$path: Unsupported FlutterGen color name or type: $name.',
          );
        }
        final offset = start.start!;
        final location = lines.getLocation(offset);
        result[name] = FlutterColor(
          name,
          members,
          path,
          offset,
          start.stop! - offset,
          location.lineNumber,
          location.columnNumber,
          outputPath,
          className,
        );
      }
    }
    final owners = <String, String>{};
    for (final color in result.values) {
      for (final member in color.members) {
        if (owners.containsKey(member)) {
          throw FormatException('FlutterGen color member collision: $member.');
        }
        owners[member] = color.name;
      }
    }
    return result.values.toList();
  }

  static Map<Object?, Object?> _merge(
    Map<Object?, Object?> left,
    Map<Object?, Object?> right,
  ) => {
    ...left,
    for (final key in right.keys)
      if (right[key] != null)
        key: left[key] is Map && right[key] is Map
            ? _merge(left[key]! as Map, right[key]! as Map)
            : right[key],
  };

  // Match FlutterGen's word splitting, including acronym handling.
  static String _camelCase(String name) {
    final separator = RegExp('[a-z]').hasMatch(name)
        ? RegExp(r'[ ./_\\@-]+|(?=[A-Z])')
        : RegExp(r'[ ./_\\@-]+');
    final words = name
        .split(separator)
        .where((word) => word.isNotEmpty)
        .map((word) => word.toLowerCase())
        .toList();
    if (words.isEmpty) return '';
    return words.first +
        words
            .skip(1)
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join();
  }
}
