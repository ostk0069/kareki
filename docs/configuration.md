# Configuration

`kareki` reads `kareki-config.yaml` from the workspace root. All keys are optional — defaults work out of the box.

## Top-level schema

| Key | Type | Purpose |
|---|---|---|
| `packages` | map | Override workspace package globs (defaults to melos.yaml / pub workspace auto-detection). |
| `exclude` | map | Files / declaration names to skip from analysis. |
| `entry_points` | map | Additional entry-point files / declaration names. |
| `keep_alive_annotations` | map | Enabled built-in presets + ad-hoc keep-alive annotation names. |
| `custom_presets` | map | Project-defined presets, or overrides of built-ins. |
| `annotation_implied_packages` | map | Standalone annotation → pub package mappings. |
| `sdk_packages` | list | Packages never flagged as `unused_pub_dependency` (SDK-provided). |
| `ignore` | map | Global / per-package suppressions. |
| `output.format` | `text` \| `json` | Default report format. |
| `baseline` | path | Path to a baseline file (relative to the workspace root). Findings recorded here are suppressed from output. |

## Defaults

| Setting | Built-in value |
|---|---|
| `exclude.files` | `.g.dart`, `.freezed.dart`, `.gr.dart`, `.generated.dart`, `.pb.dart`, `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart`, `.pbgrpc.dart`, `.config.dart`, `l10n*.dart`, `*mocks.dart` |
| `entry_points.files` | `**/*.story.dart`, `**/widgetbook/**/*.dart` |
| `keep_alive_annotations.presets` | `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta` |
| `sdk_packages` | `flutter`, `flutter_test`, `flutter_driver`, `flutter_localizations`, `flutter_web_plugins`, `integration_test`, `sky_engine` |
| Implicit entry-point conventions | `main.dart` / `main_*.dart`, `flutter_test_config.dart`, `*_test.dart` (in `test/`), any file in `bin/`, `integration_test/`, `lib/l10n/`, or any `void main()` declared under `test/` |
| Generated-file detection (content) | First lines contain `GENERATED CODE - DO NOT MODIFY BY HAND` or `AUTO-GENERATED FILE. DO NOT EDIT` |

## Built-in presets

| Preset | Keep-alive annotations | Implies pub packages |
|---|---|---|
| `freezed` | `@freezed`, `@Freezed`, `@Default`, `@Assert` | `freezed_annotation`, `built_collection` |
| `json_serializable` | `@JsonSerializable`, `@JsonKey`, `@JsonEnum`, `@JsonValue` | `json_annotation` |
| `riverpod` | `@Riverpod`, `@riverpod` | `riverpod_annotation` |
| `auto_route` | `@AutoRouterConfig`, `@RoutePage`, `@AutoRoute`, `@CustomRoute`, `@MaterialRoute`, `@CupertinoRoute`, `@AdaptiveRoute` | — |
| `go_router` | `@TypedGoRoute`, `@TypedShellRoute`, `@TypedStatefulShellRoute`, `@TypedStatefulShellBranch` | `go_router` |
| `drift` | `@DriftDatabase`, `@DriftAccessor`, `@UseRowClass` | `drift` |
| `hive` | `@HiveType`, `@HiveField` | `hive` |
| `meta` *(always on)* | `@visibleForTesting`, `@visibleForOverriding`, `@protected`, `@internal`, `@immutable`, `@experimental`, `@mustCallSuper`, `@sealed`, `@factory`, `@useResult`, `@nonVirtual`, `@pragma` | `meta` |

Definitions live in [`lib/src/preset/builtin_presets.dart`](../lib/src/preset/builtin_presets.dart) with a `last_verified` framework version on each entry.

## Defining or overriding a preset

```yaml
custom_presets:
  # Replace the built-in `freezed` preset to pin to a fork whose
  # annotation names have diverged.
  freezed:
    keep_alive_annotations: [freezed, Freezed]
    annotation_implied_packages:
      freezed: [freezed_annotation_v4]

  # Add a brand-new preset for an in-house DI codegen.
  my_internal_di:
    keep_alive_annotations: [Injectable, Singleton]
    annotation_implied_packages:
      Injectable: [my_di_package]
      Singleton: [my_di_package]
```

When `custom_presets.<name>` matches a built-in name, the built-in is **replaced entirely** — useful for pinning to a framework version whose annotation names have diverged from kareki's defaults.

## Suppression

### Inline (file-level)

```dart
// kareki: ignore_for_file=unused_element
```

```dart
// kareki: ignore_for_file=unused_element,unused_file
```

### Per-package dependency

```yaml
ignore:
  dependencies:
    my_app:
      # Flutter native plugins are auto-registered, never imported.
      - geolocator_android
      - google_sign_in_ios
```

### Global

```yaml
ignore:
  packages: [dartx, wt_cli]    # skip these workspace packages
  rules: [unused_pub_dependency]
```

## Full example

```yaml
version: 1

packages:
  include: ["packages/**", "modules/**", "."]
  exclude: ["**/build/**"]

exclude:
  files: ["**/*.fake.dart"]
  names: [debugFillProperties]

entry_points:
  files: ["**/*.story.dart"]

keep_alive_annotations:
  presets: [freezed, riverpod, auto_route, json_serializable]
  custom: [KeepAlive]

custom_presets:
  my_internal_di:
    keep_alive_annotations: [Injectable]
    annotation_implied_packages:
      Injectable: [my_di_package]

ignore:
  packages: [my_lib_package]
  dependencies:
    my_app: [geolocator_android, google_sign_in_ios]

output:
  format: text
```
