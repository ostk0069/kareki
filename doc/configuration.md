---
title: Configuration
weight: 3
---

`kareki` reads `kareki-config.yaml` from the workspace root. All keys are optional — defaults work out of the box.

## Top-level schema

| Key | Type | Purpose |
|---|---|---|
| `packages` | map | Override workspace package globs (defaults to melos.yaml / pub workspace auto-detection). |
| `exclude` | map | Files, declaration names, or parameter names to skip from analysis. |
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
| `exclude.files` | `.g.dart`, `.freezed.dart`, `.gr.dart`, `.generated.dart`, `.drift.dart`, `.steps.dart`, `.pb.dart`, `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart`, `.pbgrpc.dart`, `.config.dart`, `l10n*.dart`, `*mocks.dart` |
| `entry_points.files` | `**/*.story.dart`, `**/widgetbook/**/*.dart` |
| `keep_alive_annotations.presets` | `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta` |
| `sdk_packages` | `flutter`, `flutter_test`, `flutter_driver`, `flutter_localizations`, `flutter_web_plugins`, `integration_test`, `sky_engine` |
| Implicit entry-point conventions | `main.dart` / `main_*.dart`, `flutter_test_config.dart`, `*_test.dart` (in `test/`), any file in `bin/`, `integration_test/`, `lib/l10n/`, or any collected file with a top-level `main` |
| Generated-file detection (content) | First lines contain `GENERATED CODE - DO NOT MODIFY BY HAND` or `AUTO-GENERATED FILE. DO NOT EDIT` |

## Source collection and generated files

Source collection includes Dart files directly in each package root and under
`lib/`, `bin/`, `test/`, `integration_test/`, `example/`, `tool/`, and `tools/`.
`build/`, `.dart_tool/`, and `.git/` directories are pruned; discovered nested packages own their
files without duplicate collection under the parent. Any collected file
with a top-level `main` is an executable entry point. Other script helpers are
not automatically kept alive. Nonstandard source directories are not discovered
merely by listing them in `entry_points.files`.

For packages with `flutter: {generate: true}`, Flutter gen-l10n outputs are
recognized using `l10n.yaml` (`arb-dir`, `output-dir`, `output-localization-file`)
and locales in ARB inputs. Defaults are `lib/l10n` and `app_localizations.dart`.
Only matching output paths are exempted from findings; their outgoing references
still count. An entire generated directory or every `app_localizations*.dart`
file is not blindly excluded. Legacy `synthetic-package: true` output is not
classified by this source-output rule. Run generation before analysis; this
recognition does not create missing output files.

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

The built-in `drift` preset also preserves column declarations of reachable
`package:drift` `Table` subtypes, including inherited and mixin columns. These are
inputs to schema generation even when generated code overrides the original
getters. Unrelated same-named types and unused tables are not kept alive by this
rule. Replacing the `drift` preset also replaces this built-in behavior.

The built-in `freezed` preset preserves redirecting factories on types annotated
with the resolved `Freezed` type from `package:freezed_annotation` (including
`@freezed`). They define generated variants even when all callers instantiate
the generated class directly. Ordinary factory bodies and same-named annotations
from other libraries do not activate this rule. Disabling or replacing the
`freezed` preset disables these additional edges.

Drift schema snapshots and `flutter_rust_bridge` files are recognized by their
generator-specific headers. Generated files are excluded from findings, but
their imports, references and argument usage still participate in analysis.

`unused_pub_dependency` retains dependencies whose resolved `pubspec.yaml`
declares a native Flutter plugin (`ffiPlugin: true` or a nonempty `pluginClass`).
Flutter can register or bundle these without a Dart import. The check reads the
nearest `.dart_tool/package_config.json`, so run `pub get` first. This is a
conservative build-dependency exemption, not proof that every plugin is needed
on every target platform. Ordinary Dart dependencies remain checked.

## Suppression

### Inline (file-level)

```dart
// kareki: ignore_for_file=unused_element
```

```dart
// kareki: ignore_for_file=unused_element,unused_file
```

### Inline (per-line)

Suppress findings on a single line with `// kareki: ignore=<rule|name>`. Standalone comments target the next non-blank, non-comment line; trailing comments target their own line.

```dart
// kareki: ignore=unused_element
class Dead {}

class Other {} // kareki: ignore=unused_element

void foo({
  int? unused, // kareki: ignore=unused_parameter_optional
}) {}
```

Multiple rules / symbol names can be comma-separated:

```dart
// kareki: ignore=unused_element, MyClass
class MyClass {}
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

To keep the unused-parameter rules enabled while allowing intentionally
retained parameters with specific names across the workspace, use an exact-name
allowlist:

```yaml
exclude:
  parameter_names: [context]
```

`exclude.parameter_names` applies only to `unused_parameter` and
`unused_parameter_optional`. It does not suppress declarations with the same
name. `kareki doctor` reports entries that suppress no current finding.

## Full example

```yaml
version: 1

packages:
  include: ["packages/**", "modules/**", "."]
  exclude: ["**/build/**"]

exclude:
  files: ["**/*.fake.dart"]
  names: [debugFillProperties]
  parameter_names: [context]

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
