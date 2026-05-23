# kareki

[![pub package](https://img.shields.io/pub/v/kareki.svg)](https://pub.dev/packages/kareki)
[![CI](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml/badge.svg)](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

> 枯木 (kareki, German *Totholz*): dead wood — the unused branches that need pruning.

A multi-package dead-code detector for Dart and Flutter monorepos.

`dart analyze` only flags **private** unused declarations within a single package. `kareki` finds **public** unused APIs, **untouched files**, and **stale pub dependencies** across an entire workspace — Melos or pub workspaces — by resolving cross-package references and respecting the conventions of popular code generators (freezed, json_serializable, riverpod, auto_route, go_router, drift, hive).

## Features

| Rule | Detects |
|---|---|
| `unused_element` | Public classes / functions / methods / getters / setters / fields / top-level variables / extensions / typedefs with no caller anywhere in the workspace. |
| `unused_file` | `.dart` files that are not `import`-ed, `part`-ed, or `export`-ed from any other file. |
| `unused_pub_dependency` | Packages declared in `pubspec.yaml` whose imports never appear in source. |
| `test_only_used` | Public declarations under `lib/` that are only referenced from test code (`*_test.dart`, files under `test/` or `integration_test/`). The implementation has no production consumer — typically its tests are the only thing keeping it alive. |

## Installation

```yaml
# pubspec.yaml
dev_dependencies:
  kareki: ^0.1.0
```

```sh
dart pub get
```

## Usage

Run from the workspace root:

```sh
dart run kareki
```

### CLI options

| Option | Description |
|---|---|
| `--root <path>` | Workspace root. Defaults to the current directory. |
| `-f`, `--format <name>` | Output format: `text` \| `json`. Overrides `kareki-config.yaml`. |
| `--packages <name>` | Restrict analysis to these packages. Repeatable. |
| `--rule <id>` | Enable only these rules. Repeatable. |
| `--strict` | Treat `dev_dependencies` the same as `dependencies` for `unused_pub_dependency`. |
| `-h`, `--help` | Show usage. |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | No findings. |
| `1` | One or more findings reported. |
| `64` | Invalid CLI usage. |

## Configuration

`kareki` reads `kareki-config.yaml` from the workspace root. All keys are optional — defaults work out of the box.

### Top-level schema

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
| `baseline` | path | Path to a baseline file (planned). |

### Defaults

| Setting | Built-in value |
|---|---|
| `exclude.files` | `.g.dart`, `.freezed.dart`, `.gr.dart`, `.generated.dart`, `.pb.dart`, `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart`, `.pbgrpc.dart`, `.config.dart`, `l10n*.dart`, `*mocks.dart` |
| `entry_points.files` | `**/*.story.dart`, `**/widgetbook/**/*.dart` |
| `keep_alive_annotations.presets` | `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta` |
| `sdk_packages` | `flutter`, `flutter_test`, `flutter_driver`, `flutter_localizations`, `flutter_web_plugins`, `integration_test`, `sky_engine` |
| Implicit entry-point conventions | `main.dart` / `main_*.dart`, `flutter_test_config.dart`, `*_test.dart` (in `test/`), any file in `bin/`, `integration_test/`, `lib/l10n/`, or any `void main()` declared under `test/` |
| Generated-file detection (content) | First lines contain `GENERATED CODE - DO NOT MODIFY BY HAND` or `AUTO-GENERATED FILE. DO NOT EDIT` |

### Built-in presets

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

Definitions live in [`lib/src/preset/builtin_presets.dart`](lib/src/preset/builtin_presets.dart) with a `last_verified` framework version on each entry.

### Defining or overriding a preset

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

### Suppression

#### Inline (file-level)

```dart
// kareki: ignore_for_file=unused_element
```

```dart
// kareki: ignore_for_file=unused_element,unused_file
```

#### Per-package dependency

```yaml
ignore:
  dependencies:
    my_app:
      # Flutter native plugins are auto-registered, never imported.
      - geolocator_android
      - google_sign_in_ios
```

#### Global

```yaml
ignore:
  packages: [dartx, wt_cli]    # skip these workspace packages
  rules: [unused_pub_dependency]
```

### Full example

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

## How it works

1. Discover packages via `melos.yaml` or pub workspace.
2. Parse every `.dart` file with `package:analyzer`, extracting declarations + outgoing simple-name references.
3. Resolve entry points (implicit conventions + active presets + generated-file references + config).
4. BFS the simple-name graph from those root identifiers.
5. Report unreached declarations, unreferenced files, and undeclared pub deps.

Entry-point seeding combines four layers:

| Layer | Source |
|---|---|
| Implicit | Dart / Flutter SDK conventions (`main`, `_test`, `bin/`, `integration_test/`, `lib/l10n/`, `flutter_test_config.dart`). |
| Tool conventions | `entry_points.files` config (defaults: playbook / widgetbook globs). |
| Annotations | Active preset keep-alives + `custom_presets.*.keep_alive_annotations` + `keep_alive_annotations.custom`. |
| Generated code | Files matching `exclude.files` or carrying a `GENERATED CODE` header — their identifier references seed BFS roots. |

This layered design lets kareki coexist with codegen-heavy ecosystems without flooding you with false positives.

## Supported versions

| Component | Version |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `^9.0.0` |

Newer analyzer versions will be added incrementally; the choice of 9.x lets projects that have not yet migrated to analyzer 10+ adopt kareki today.

## License

MIT. See [LICENSE](LICENSE).
