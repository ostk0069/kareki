import 'package:kareki/src/preset/builtin_presets.dart';
import 'package:kareki/src/preset/preset.dart';

/// Resolves the final set of active presets by merging built-in
/// defaults with user-supplied overrides.
///
/// Resolution order:
/// 1. Built-in presets whose [Preset.name] appears in [enabledPresetNames].
/// 2. User-supplied [customPresets]. When a custom preset's name matches
///    a built-in (or another custom), it **replaces** the previous entry
///    — allowing projects to redefine a preset for a specific framework
///    version whose annotation names diverge from the built-in
///    expectations.
///
/// Custom presets are always active regardless of [enabledPresetNames];
/// declaring a preset in `custom_presets` is itself an opt-in signal.
class PresetRegistry {
  PresetRegistry({
    required Set<String> enabledPresetNames,
    List<Preset> customPresets = const [],
  }) : _enabledPresetNames = enabledPresetNames,
       _customPresets = customPresets;

  final Set<String> _enabledPresetNames;
  final List<Preset> _customPresets;

  late final List<Preset> _resolved = _resolve();

  List<Preset> _resolve() {
    final byName = <String, Preset>{};
    // `meta` is universal (not framework-specific) — its annotations
    // (`@visibleForTesting`, `@internal`, `@protected`, etc.) are part
    // of the Dart base library convention rather than any opt-in tool.
    // Always include it so projects don't need to remember to enable
    // it explicitly. Users can still override its contents via a
    // `custom_presets.meta` entry.
    byName[metaPreset.name] = metaPreset;
    for (final preset in allBuiltInPresets) {
      if (_enabledPresetNames.contains(preset.name)) {
        byName[preset.name] = preset;
      }
    }
    for (final preset in _customPresets) {
      byName[preset.name] = preset;
    }
    return byName.values.toList();
  }

  /// All keep-alive annotation simple names from active presets.
  Set<String> get keepAliveAnnotations => {
    for (final preset in _resolved) ...preset.keepAliveAnnotations,
  };

  /// Union of annotation → implied pub packages across active presets.
  Map<String, Set<String>> get annotationImpliedPackages {
    final result = <String, Set<String>>{};
    for (final preset in _resolved) {
      preset.annotationImpliedPackages.forEach((annotation, packages) {
        result.putIfAbsent(annotation, () => <String>{}).addAll(packages);
      });
    }
    return result;
  }
}
