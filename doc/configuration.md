---
title: Configuration
weight: 3
---

Use `kareki-config.yaml` at the workspace root to choose packages, retain code
used by your tools, and suppress findings you intend to keep. The file and all
settings are optional; start with defaults and add only the overrides you need.
Check the [list replacement rules](#replacing-default-lists) before overriding a default list.
For setup and command options, see the [CLI reference](cli.md). For how kareki
decides whether code is used, see [How it works](how-it-works.md).

## Packages and entry points

| Key | Value | Default / effect |
|---|---|---|
| `packages.include` | Package-directory globs | Auto-detect from Melos / pub workspace settings, or use the root package, when omitted or empty. A nonempty list replaces auto-detection. |
| `packages.exclude` | Package-directory globs | Adds to Melos `ignore` when auto-detecting; otherwise none. Removes matching packages from discovery, including their references. |
| `entry_points.files` | File globs | `**/*.story.dart`, `**/widgetbook/**/*.dart`. Retains declarations in matching files. |
| `entry_points.names` | Exact declaration names | None. Retains matching declarations. |

`entry_points.files` retains declarations in matching files within the
[scanned source scope](how-it-works.md#source-scope-and-reporting-scope);
it does not add source directories.

Dart / Flutter entry-point conventions remain active regardless of these
settings: top-level `main`, `main.dart` / `main_*.dart`, `flutter_test_config.dart`,
`*_test.dart` under `test/`, and files in `bin/`, `integration_test/`, or `lib/l10n/`.

For example, retain a framework callback that has no visible caller:

```yaml
entry_points:
  names: [registerBackgroundHandler]
```

## Suppression

Use suppression when a finding is intentional. File and package report
exclusions still contribute references to other code.

| Key | Value | Suppresses |
|---|---|---|
| `exclude.files` | File globs | Findings in matching Dart or ARB files. See defaults below. |
| `exclude.names` | Exact names | Matching declaration or localization-key findings. |
| `exclude.parameter_names` | Exact names | Only `unused_parameter` and `unused_parameter_optional` findings. |
| `ignore.packages` | Pub package names | All findings in those packages. |
| `ignore.rules` | Rule IDs | All findings for those rules. |
| `ignore.dependencies` | Package name → dependency-name list | `unused_pub_dependency` findings for the listed dependencies in each package. |
| `baseline` | File path, relative to workspace root | Previously recorded findings. See [baseline options](cli.md#options). |

By default, `exclude.files` contains `**/` globs for these filename patterns:

```text
*.g.dart          *.freezed.dart   *.gr.dart         *.generated.dart
*.drift.dart      *.steps.dart     *.pb.dart         *.pbenum.dart
*.pbjson.dart     *.pbserver.dart  *.pbgrpc.dart     *.config.dart
l10n*.dart        *mocks.dart
```

Generated-file headers and configured Flutter gen-l10n outputs are also
recognized automatically; see [generated code](how-it-works.md#5-generated-code-can-be-the-only-caller).

For example, allow a retained parameter and a dependency used by a build script:

```yaml
exclude:
  parameter_names: [context]
ignore:
  dependencies:
    my_app: [custom_build_support]
```

### Inline comments

Use Dart comments for a local exception instead of a workspace-wide setting:

```dart
// kareki: ignore_for_file=unused_element,unused_file

// kareki: ignore=unused_element
class Dead {}

void foo({
  int? unused, // kareki: ignore=unused_parameter_optional
}) {}
```

`ignore_for_file` applies to the whole file. `ignore` applies to its own line
when trailing code, or to the next non-blank, non-comment line when standalone.
Comma-separated values can be rule IDs or, for `ignore`, symbol names.
ARB files cannot use these comments; use the settings above for localization keys.
[Doctor](doctor.md) finds suppressions that no longer match a finding.

## Built-in presets

Presets retain annotated declarations used by generators and recognize the
annotations' implied dependencies. All presets below are enabled by default.

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

| Key | Value | Default / effect |
|---|---|---|
| `keep_alive_annotations.presets` | Preset names | All built-ins above. A nonempty list selects which to enable; `meta` stays active. |
| `keep_alive_annotations.custom` | Annotation names without `@` | None. Retains declarations with these annotations. |
| `custom_presets` | Preset name → definition | None. Each definition is always active; matching a built-in name replaces that preset entirely. |
| `annotation_implied_packages` | Annotation name → pub-package list | None. Adds dependency mappings to the active presets. |

For example, select the generators used by your project and add an annotation:

```yaml
keep_alive_annotations:
  presets: [freezed, json_serializable, riverpod]
  custom: [KeepAlive]
```

The `freezed` and `drift` presets also protect schema-generation inputs.
Replacing either preset removes those protections; see
[schema generation inputs](how-it-works.md#schema-generation-inputs).

### Defining or overriding a preset

```yaml
custom_presets:
  my_internal_di:
    keep_alive_annotations: [Injectable, Singleton]
    annotation_implied_packages:
      Injectable: [my_di_package]
      Singleton: [my_di_package]

  # Replace the built-in preset for a framework fork.
  freezed:
    keep_alive_annotations: [freezed, Freezed]
    annotation_implied_packages:
      freezed: [freezed_annotation_v4]
      Freezed: [freezed_annotation_v4]
```

## Unused localization keys

`unused_l10n` reads Flutter's `pubspec.yaml` and `l10n.yaml`; it has no separate
kareki configuration. Enable `flutter.generate: true`, generate the code, and
resolve workspace dependencies before running `dart run kareki --rule unused_l10n`.

| Flutter setting | Default |
|---|---|
| `arb-dir` | `lib/l10n` |
| `template-arb-file` | `app_en.arb` |
| `output-dir` | The ARB directory |
| `output-localization-file` | `app_localizations.dart` |
| `output-class` | `AppLocalizations` |

Persist custom paths, template names, and class names in `l10n.yaml` so kareki
can discover them. Generator command-line overrides alone are not discoverable.
Flutter Intl / `intl_utils`, `easy_localization`, `slang`, legacy synthetic
packages, and paths outside the package are unsupported.

Findings point to keys in the template ARB. Suppress them with `exclude.names`,
ARB globs in `exclude.files`, `ignore.rules`, or a baseline. Exclusions do not
skip input validation. See [localization-key analysis](how-it-works.md#localization-key-analysis)
for what counts as usage, warnings, and validation failures.

## SDK packages and output

| Key | Value | Default / effect |
|---|---|---|
| `sdk_packages` | Pub package names | `flutter`, `flutter_test`, `flutter_driver`, `flutter_localizations`, `flutter_web_plugins`, `integration_test`, `sky_engine`. Never reported as unused dependencies. Override for SDK forks. |
| `output.format` | `text` or `json` | `text`. The CLI `--format` option takes precedence. |

## Replacing default lists

`exclude.files` and `entry_points.files` **replace**, rather than extend, their
default lists. Include default patterns you still need; `[]` clears the list.
For example, to keep the story convention but stop treating widgetbook files
as entry points:

```yaml
entry_points:
  files: ["**/*.story.dart"]
```

`keep_alive_annotations.presets` and `sdk_packages` also replace their defaults
when nonempty, but `[]` uses the defaults. `meta` remains active even when omitted
from the selected presets; override it through `custom_presets.meta` if needed.
