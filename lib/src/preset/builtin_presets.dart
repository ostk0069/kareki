import 'package:kareki/src/preset/preset.dart';

/// Built-in presets for popular Flutter / Dart ecosystem frameworks.
///
/// Each entry encodes the framework's annotation conventions as of the
/// `last_verified` version in its docstring. Override or extend via the
/// `custom_presets` section of `kareki_config.yaml` when a project uses
/// a different version whose annotation names diverge.

/// freezed — last_verified: freezed 3.x.
const Preset freezedPreset = Preset(
  name: 'freezed',
  keepAliveAnnotations: {'freezed', 'Freezed', 'Default', 'Assert'},
  annotationImpliedPackages: {
    'freezed': {'freezed_annotation', 'built_collection'},
    'Freezed': {'freezed_annotation', 'built_collection'},
    'Default': {'freezed_annotation'},
    'Assert': {'freezed_annotation'},
  },
);

/// json_serializable — last_verified: json_serializable 6.x /
/// json_annotation 4.x.
const Preset jsonSerializablePreset = Preset(
  name: 'json_serializable',
  keepAliveAnnotations: {
    'JsonSerializable',
    'JsonKey',
    'JsonEnum',
    'JsonValue',
  },
  annotationImpliedPackages: {
    'JsonSerializable': {'json_annotation'},
    'JsonKey': {'json_annotation'},
    'JsonEnum': {'json_annotation'},
    'JsonValue': {'json_annotation'},
  },
);

/// riverpod — last_verified: riverpod 2.x / riverpod_annotation 2.x.
const Preset riverpodPreset = Preset(
  name: 'riverpod',
  keepAliveAnnotations: {'Riverpod', 'riverpod'},
  annotationImpliedPackages: {
    'Riverpod': {'riverpod_annotation'},
    'riverpod': {'riverpod_annotation'},
  },
);

/// auto_route — last_verified: auto_route 9.x.
const Preset autoRoutePreset = Preset(
  name: 'auto_route',
  keepAliveAnnotations: {
    'AutoRouterConfig',
    'RoutePage',
    'AutoRoute',
    'CustomRoute',
    'MaterialRoute',
    'CupertinoRoute',
    'AdaptiveRoute',
  },
);

/// go_router with go_router_builder — last_verified: go_router 14.x.
///
/// Plain `go_router` (no codegen) doesn't use annotations and doesn't
/// need this preset — routes are declared as plain `GoRoute(...)` calls
/// whose `builder:` reference keeps the page widgets reachable via the
/// normal BFS.
///
/// This preset only affects projects that opt into the
/// `go_router_builder` dev dependency to declare typed routes with
/// `@TypedGoRoute<T>` and friends; the route classes are then
/// referenced exclusively from generated `*.g.dart` files. Annotations
/// themselves live in `package:go_router`, so that's the implied
/// pub package.
const Preset goRouterPreset = Preset(
  name: 'go_router',
  keepAliveAnnotations: {
    'TypedGoRoute',
    'TypedShellRoute',
    'TypedStatefulShellRoute',
    'TypedStatefulShellBranch',
  },
  annotationImpliedPackages: {
    'TypedGoRoute': {'go_router'},
    'TypedShellRoute': {'go_router'},
    'TypedStatefulShellRoute': {'go_router'},
    'TypedStatefulShellBranch': {'go_router'},
  },
);

/// drift — last_verified: drift 2.x.
const Preset driftPreset = Preset(
  name: 'drift',
  keepAliveAnnotations: {'DriftDatabase', 'DriftAccessor', 'UseRowClass'},
  annotationImpliedPackages: {
    'DriftDatabase': {'drift'},
    'DriftAccessor': {'drift'},
  },
);

/// hive — last_verified: hive 2.x.
const Preset hivePreset = Preset(
  name: 'hive',
  keepAliveAnnotations: {'HiveType', 'HiveField'},
  annotationImpliedPackages: {
    'HiveType': {'hive'},
    'HiveField': {'hive'},
  },
);

/// package:meta — last_verified: meta 1.x.
///
/// Annotations from `package:meta`. Even when re-exported by
/// `package:flutter/foundation.dart` or `package:freezed_annotation`,
/// any package that uses these annotations directly should declare
/// `meta` in pubspec to be safe; the preset reflects that.
const Preset metaPreset = Preset(
  name: 'meta',
  keepAliveAnnotations: {
    'visibleForTesting',
    'visibleForOverriding',
    'protected',
    'internal',
    'immutable',
    'experimental',
    'mustCallSuper',
    'sealed',
    'factory',
    'useResult',
    'nonVirtual',
    'pragma',
  },
  annotationImpliedPackages: {
    'visibleForTesting': {'meta'},
    'visibleForOverriding': {'meta'},
    'protected': {'meta'},
    'internal': {'meta'},
    'immutable': {'meta'},
    'experimental': {'meta'},
    'mustCallSuper': {'meta'},
    'sealed': {'meta'},
    'factory': {'meta'},
    'useResult': {'meta'},
    'nonVirtual': {'meta'},
  },
);

/// All built-in presets. The runtime [PresetRegistry] selects from this
/// list based on the user's `keep_alive_annotations.presets` config.
const List<Preset> allBuiltInPresets = [
  freezedPreset,
  jsonSerializablePreset,
  riverpodPreset,
  autoRoutePreset,
  goRouterPreset,
  driftPreset,
  hivePreset,
  metaPreset,
];

/// Built-in SDK package names. Imports of these never indicate a
/// project pub dependency because they ship with the Flutter / Dart
/// SDK and are declared in pubspec with `sdk:` instead of a version
/// constraint.
///
/// Override via `sdk_packages:` in `kareki_config.yaml` for forks or
/// custom SDK layouts.
const Set<String> builtInSdkPackages = {
  'flutter',
  'flutter_test',
  'flutter_driver',
  'flutter_localizations',
  'flutter_web_plugins',
  'integration_test',
  'sky_engine',
};
