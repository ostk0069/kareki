import 'dart:io';

import 'package:kareki/src/preset/builtin_presets.dart';
import 'package:kareki/src/preset/preset.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Output report formats.
enum OutputFormat { text, json }

/// Parsed configuration from `kareki-config.yaml`.
class KarekiConfig {
  KarekiConfig({
    required this.includePackages,
    required this.excludePackages,
    required this.excludeFiles,
    required this.excludeNames,
    required this.entryPointFiles,
    required this.entryPointNames,
    required this.enabledPresetNames,
    required this.customPresets,
    required this.customKeepAliveAnnotations,
    required this.ignorePackages,
    required this.ignoreRules,
    required this.ignoredDependencies,
    required this.annotationImpliedPackages,
    required this.sdkPackages,
    required this.output,
    required this.baselinePath,
  });

  factory KarekiConfig.defaults() => KarekiConfig(
    ignoredDependencies: const {},
    annotationImpliedPackages: const {},
    includePackages: const [],
    excludePackages: const [],
    excludeFiles: const [
      '**/*.g.dart',
      '**/*.freezed.dart',
      '**/*.gr.dart',
      '**/*.generated.dart',
      '**/*.pb.dart',
      '**/*.pbenum.dart',
      '**/*.pbjson.dart',
      '**/*.pbserver.dart',
      '**/*.pbgrpc.dart',
      '**/*.config.dart',
      '**/l10n*.dart',
      '**/*mocks.dart',
    ],
    excludeNames: const {},
    // Tool-specific entry-point conventions that aren't part of the
    // Dart / Flutter SDK. Override `entry_points.files` in
    // `kareki-config.yaml` to disable or replace.
    entryPointFiles: const [
      // playbook_flutter: each `*.story.dart` file declares a UI
      // catalog scenario, picked up by the snapshot test runner.
      '**/*.story.dart',
      // widgetbook: every file under a `widgetbook/` directory is
      // consumed by the widgetbook runner.
      '**/widgetbook/**/*.dart',
    ],
    entryPointNames: const {},
    enabledPresetNames: const {
      'freezed',
      'json_serializable',
      'riverpod',
      'auto_route',
      'go_router',
      'drift',
      'hive',
      'meta',
    },
    customPresets: const [],
    customKeepAliveAnnotations: const {},
    ignorePackages: const {},
    ignoreRules: const {},
    sdkPackages: builtInSdkPackages,
    output: OutputFormat.text,
    baselinePath: null,
  );

  /// Glob patterns for packages to include (overrides melos.yaml when set).
  final List<String> includePackages;

  /// Glob patterns for packages to exclude.
  final List<String> excludePackages;

  /// Glob patterns for files to exclude from analysis.
  final List<String> excludeFiles;

  /// Declaration simple names to always ignore.
  final Set<String> excludeNames;

  /// Glob patterns for additional entry-point files.
  final List<String> entryPointFiles;

  /// Declaration simple names to treat as entry points.
  final Set<String> entryPointNames;

  /// Names of built-in presets to enable. Custom presets defined in
  /// [customPresets] are always enabled regardless of this set.
  final Set<String> enabledPresetNames;

  /// Project-defined presets. When a custom preset's name matches a
  /// built-in, it **replaces** the built-in entirely — letting a
  /// project pin to a specific framework version whose annotation names
  /// diverge from the kareki defaults.
  final List<Preset> customPresets;

  /// Ad-hoc keep-alive annotation simple names that don't belong to a
  /// preset. Use [customPresets] when you also need to declare implied
  /// pub packages for the annotation.
  final Set<String> customKeepAliveAnnotations;

  /// Package names to skip entirely.
  final Set<String> ignorePackages;

  /// Rule ids to suppress (e.g. `unused_pub_dependency`).
  final Set<String> ignoreRules;

  /// Per-package list of dep names to suppress from
  /// `unused_pub_dependency`. Use this for packages declared at runtime
  /// (Flutter native plugins, transitive build_runner annotation
  /// packages, etc.) that are intentionally listed even though no source
  /// file imports them.
  final Map<String, Set<String>> ignoredDependencies;

  /// Top-level annotation → implied pub packages, merged on top of
  /// every active preset's mapping. Use for one-off annotations that
  /// don't justify a full preset.
  final Map<String, Set<String>> annotationImpliedPackages;

  /// Packages that ship with the SDK and never count toward
  /// `unused_pub_dependency`. Defaults to [builtInSdkPackages] for
  /// stock Flutter / Dart projects; override for forks or custom SDK
  /// layouts.
  final Set<String> sdkPackages;

  final OutputFormat output;

  /// Path to baseline file (resolved relative to project root).
  final String? baselinePath;

  /// Load configuration from `kareki-config.yaml` in the given root,
  /// returning defaults when the file is absent.
  ///
  /// Also accepts the legacy filenames `kareki_config.yaml` and
  /// `kareki.yaml` for backwards compatibility with early adopters.
  static KarekiConfig load(String rootPath) {
    const candidates = [
      'kareki-config.yaml',
      'kareki_config.yaml',
      'kareki.yaml',
    ];
    File? file;
    for (final name in candidates) {
      final candidate = File(p.join(rootPath, name));
      if (candidate.existsSync()) {
        file = candidate;
        break;
      }
    }
    if (file == null) return KarekiConfig.defaults();
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) return KarekiConfig.defaults();
    final defaults = KarekiConfig.defaults();

    final packages = yaml['packages'] as YamlMap?;
    final exclude = yaml['exclude'] as YamlMap?;
    final entryPoints = yaml['entry_points'] as YamlMap?;
    final keepAlive = yaml['keep_alive_annotations'] as YamlMap?;
    final ignore = yaml['ignore'] as YamlMap?;
    final output = yaml['output'] as YamlMap?;

    return KarekiConfig(
      includePackages: _stringList(packages?['include']),
      excludePackages: _stringList(packages?['exclude']),
      excludeFiles: _stringList(
        exclude?['files'],
        fallback: defaults.excludeFiles,
      ),
      excludeNames: _stringSet(exclude?['names']),
      entryPointFiles: _stringList(
        entryPoints?['files'],
        fallback: defaults.entryPointFiles,
      ),
      entryPointNames: _stringSet(entryPoints?['names']),
      enabledPresetNames: _stringSet(keepAlive?['presets']).isNotEmpty
          ? _stringSet(keepAlive?['presets'])
          : defaults.enabledPresetNames,
      customPresets: _parseCustomPresets(yaml['custom_presets']),
      customKeepAliveAnnotations: _stringSet(keepAlive?['custom']),
      ignorePackages: _stringSet(ignore?['packages']),
      ignoreRules: _stringSet(ignore?['rules']),
      ignoredDependencies: _parseStringSetMap(ignore?['dependencies']),
      annotationImpliedPackages: _parseStringSetMap(
        yaml['annotation_implied_packages'],
      ),
      sdkPackages: _stringSet(yaml['sdk_packages']).isNotEmpty
          ? _stringSet(yaml['sdk_packages'])
          : defaults.sdkPackages,
      output: _parseFormat(output?['format']) ?? defaults.output,
      baselinePath: yaml['baseline']?.toString(),
    );
  }

  static List<Preset> _parseCustomPresets(Object? node) {
    if (node is! YamlMap) return const [];
    final result = <Preset>[];
    for (final entry in node.entries) {
      final value = entry.value;
      if (value is! YamlMap) continue;
      result.add(
        Preset(
          name: entry.key.toString(),
          keepAliveAnnotations: _stringSet(value['keep_alive_annotations']),
          annotationImpliedPackages: _parseStringSetMap(
            value['annotation_implied_packages'],
          ),
        ),
      );
    }
    return result;
  }

  static Map<String, Set<String>> _parseStringSetMap(Object? node) {
    if (node is! YamlMap) return const {};
    return {
      for (final entry in node.entries)
        entry.key.toString(): _stringSet(entry.value),
    };
  }

  static List<String> _stringList(
    Object? node, {
    List<String> fallback = const [],
  }) {
    if (node is YamlList) {
      return node.map((e) => e.toString()).toList();
    }
    return fallback;
  }

  static Set<String> _stringSet(Object? node) {
    if (node is YamlList) {
      return node.map((e) => e.toString()).toSet();
    }
    return const {};
  }

  static OutputFormat? _parseFormat(Object? node) {
    switch (node?.toString()) {
      case 'text':
        return OutputFormat.text;
      case 'json':
        return OutputFormat.json;
    }
    return null;
  }
}
