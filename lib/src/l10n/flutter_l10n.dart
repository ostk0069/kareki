import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One configured gen-l10n resource family, independent of analyzer objects.
class FlutterL10n {
  FlutterL10n({
    required this.packageName,
    required this.templatePath,
    required this.outputPath,
    required this.className,
    required this.keys,
    required this.outputPaths,
  });

  final String packageName;
  final String templatePath;
  final String outputPath;
  final String className;
  final Map<String, L10nKey> keys;
  final Set<String> outputPaths;

  /// Load only standard Flutter gen-l10n configurations. No generator is run.
  static FlutterL10n? load(
    String root,
    String packageName,
    Set<String> outputPaths,
  ) {
    final pubspec = loadYaml(
      File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
    );
    if (pubspec is! YamlMap || pubspec['flutter'] is! YamlMap) return null;
    if ((pubspec['flutter'] as YamlMap)['generate'] != true) return null;
    final file = File(p.join(root, 'l10n.yaml'));
    final Object? yaml = file.existsSync()
        ? loadYaml(file.readAsStringSync(), sourceUrl: file.uri)
        : null;
    if (file.existsSync() && yaml is! YamlMap) {
      throw const FormatException('l10n.yaml must contain a mapping.');
    }
    final options = yaml as YamlMap?;
    final flutterIntl = pubspec['flutter_intl'];
    // Third-party generators can share lib/l10n and generate:true. They do not
    // constitute a standard gen-l10n family without a standard config/output.
    if (!file.existsSync() &&
        !File(p.join(root, 'lib/l10n/app_localizations.dart')).existsSync() &&
        ((flutterIntl is YamlMap && flutterIntl['enabled'] == true) ||
            File(p.join(root, 'slang.yaml')).existsSync())) {
      return null;
    }
    String option(String name, String fallback) {
      if (options == null || !options.containsKey(name)) return fallback;
      final value = options[name];
      if (value is! String || value.isEmpty) {
        throw FormatException('$name must be a non-empty string.');
      }
      return value;
    }

    for (final name in [
      'nullable-getter',
      'use-deferred-loading',
      'use-named-parameters',
    ]) {
      if ((options?.containsKey(name) ?? false) && options![name] is! bool) {
        throw FormatException('$name must be a boolean.');
      }
    }
    final arbDir = option('arb-dir', 'lib/l10n');
    final input = p.normalize(p.join(root, arbDir));
    final outputDir = option('output-dir', arbDir);
    final output = p.normalize(p.join(root, outputDir));
    final template = option('template-arb-file', 'app_en.arb');
    final outputFile = option(
      'output-localization-file',
      'app_localizations.dart',
    );
    final className = option('output-class', 'AppLocalizations');
    if (!p.isWithin(root, input) ||
        !(p.equals(root, output) || p.isWithin(root, output)) ||
        p.basename(template) != template ||
        !template.endsWith('.arb') ||
        p.basename(outputFile) != outputFile ||
        !outputFile.endsWith('.dart') ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(className)) {
      throw const FormatException(
        'Unsupported gen-l10n paths or output-class.',
      );
    }
    if (options?.containsKey('synthetic-package') ?? false) {
      final synthetic = options!['synthetic-package'];
      if (synthetic is! bool || synthetic) {
        throw const FormatException('synthetic-package: true is unsupported.');
      }
    }
    final directory = Directory(input);
    // generate:true also enables other Flutter generators. An unconfigured
    // package without any ARB input is not a localization package.
    if (!file.existsSync() &&
        (!directory.existsSync() ||
            !directory.listSync().whereType<File>().any(
              (f) => p.extension(f.path) == '.arb',
            ))) {
      return null;
    }
    final templatePath = p.join(input, template);
    Map<String, L10nKey>? keys;
    if (!directory.existsSync()) {
      throw FileSystemException('ARB directory is missing', input);
    }
    for (final arb
        in directory.listSync(followLinks: false).whereType<File>()) {
      if (p.extension(arb.path) != '.arb') continue;
      final parsed = _readArb(arb);
      if (p.equals(arb.path, templatePath)) keys = parsed;
    }
    if (keys == null) {
      throw FileSystemException('Template ARB is missing', templatePath);
    }
    final outputPath = p.join(output, outputFile);
    if (keys.isNotEmpty && !File(outputPath).existsSync()) {
      throw FileSystemException(
        'Generated localization file is missing; run flutter gen-l10n',
        outputPath,
      );
    }
    return FlutterL10n(
      packageName: packageName,
      templatePath: templatePath,
      outputPath: outputPath,
      className: className,
      keys: keys,
      outputPaths: {...outputPaths, outputPath},
    );
  }
}

class L10nKey {
  L10nKey(this.name, this.line, this.column, this.length);

  final String name;
  final int line;
  final int column;
  final int length;
}

Map<String, L10nKey> _readArb(File file) {
  final source = file.readAsStringSync();
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('${file.path}: ARB must contain a JSON object.');
  }
  final locale = decoded['@@locale'];
  if (locale != null &&
      (locale is! String ||
          !RegExp(
            r'^[a-z]{2,3}(?:_[A-Z][a-z]{3})?(?:_(?:[A-Z]{2}|[0-9]{3}))?$',
          ).hasMatch(locale))) {
    throw FormatException('${file.path}: Invalid @@locale.');
  }
  // YAML's JSON-compatible parser supplies source spans and rejects duplicate
  // keys, which jsonDecode silently overwrites. JSON validity is checked above.
  final document = loadYamlNode(source, sourceUrl: file.uri) as YamlMap;
  final result = <String, L10nKey>{};
  for (final node in document.nodes.keys.cast<YamlScalar>()) {
    final name = node.value as String;
    if (name.startsWith('@')) continue;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(name) ||
        decoded[name] is! String) {
      throw FormatException(
        '${file.path}: Invalid translation key or value: $name.',
      );
    }
    result[name] = L10nKey(
      name,
      node.span.start.line + 1,
      node.span.start.column + 1,
      node.span.length,
    );
  }
  return result;
}
