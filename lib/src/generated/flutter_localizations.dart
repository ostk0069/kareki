import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Expected gen-l10n outputs, bounded by package configuration and ARB inputs.
/// This is a reporting exemption only: callers must still collect references.
Set<String> flutterLocalizationOutputs(String packageRoot) {
  final pubspec = _readYaml(File(p.join(packageRoot, 'pubspec.yaml')));
  if (pubspec is! YamlMap) return {};
  final flutter = pubspec['flutter'];
  if (flutter is! YamlMap || flutter['generate'] != true) return {};
  final configFile = File(p.join(packageRoot, 'l10n.yaml'));
  final config = configFile.existsSync() ? _readYaml(configFile) : null;
  if (config != null && config is! YamlMap) return {};
  final options = config as YamlMap?;
  if (options?['synthetic-package'] == true) return {};
  final arbDir = options?['arb-dir'] ?? 'lib/l10n';
  final outputDir = options?['output-dir'] ?? arbDir;
  final outputFile =
      options?['output-localization-file'] ?? 'app_localizations.dart';
  if (arbDir is! String || outputDir is! String || outputFile is! String) {
    return {};
  }
  final input = p.normalize(p.join(packageRoot, arbDir));
  final output = p.normalize(p.join(packageRoot, outputDir));
  if (!p.isWithin(packageRoot, input) ||
      !(p.equals(packageRoot, output) || p.isWithin(packageRoot, output)) ||
      p.basename(outputFile) != outputFile ||
      !outputFile.endsWith('.dart')) {
    return {};
  }
  final directory = Directory(input);
  if (!directory.existsSync()) return {};
  final locales = <String>{};
  final localePattern = RegExp(
    r'^[a-z]{2,3}(?:_[A-Z][a-z]{3})?(?:_(?:[A-Z]{2}|[0-9]{3}))?$',
  );
  for (final file in directory.listSync(followLinks: false).whereType<File>()) {
    if (p.extension(file.path) != '.arb') continue;
    // Respect @@locale when present; otherwise Flutter infers it from the
    // filename suffix. Invalid inputs must never exempt arbitrary Dart code.
    Object? contents;
    try {
      contents = jsonDecode(file.readAsStringSync());
    } on FormatException {
      continue;
    }
    if (contents is! Map<String, dynamic>) continue;
    final explicit = contents['@@locale'];
    final pieces = p.basenameWithoutExtension(file.path).split('_');
    final candidates = explicit == null
        ? [for (var i = 0; i < pieces.length; i++) pieces.skip(i).join('_')]
        : [explicit];
    for (final locale in candidates) {
      if (locale is! String || !localePattern.hasMatch(locale)) continue;
      locales.add(locale);
      // Flutter may group regional/script translations in a language file.
      locales.add(locale.split('_').first);
      break;
    }
  }
  if (locales.isEmpty) return {};
  // Flutter inserts the locale before the first dot, even for multi-dot names.
  final dot = outputFile.indexOf('.');
  if (dot <= 0) return {};
  final stem = outputFile.substring(0, dot);
  final suffix = outputFile.substring(dot);
  return {
    p.join(output, outputFile),
    for (final locale in locales) p.join(output, '${stem}_$locale$suffix'),
  };
}

Object? _readYaml(File file) =>
    loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
