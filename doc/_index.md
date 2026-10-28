---
title: kareki Documentation
weight: 1
cascade:
  type: docs
---

`kareki` is a workspace-wide dead code finder for Dart and Flutter. It follows references across Melos and pub workspaces to find unused public APIs, files, dependencies, and parameters that package-local analysis cannot see.

It is designed for real codebases: generated code can be described with presets, existing findings can be captured in a baseline, and configuration drift can be checked with `kareki doctor`.

## Quick start

Add `kareki` to your development dependencies:

```yaml {filename="pubspec.yaml"}
dev_dependencies:
  kareki: ^0.10.1
```

Install the project's dependencies and run code generation, then execute from
the workspace root:

```sh
dart run kareki
```

## What it finds

| Rule | Finds |
|---|---|
| `unused_element` | Public declarations with no caller in the workspace |
| `unused_file` | Dart files that are never imported, exported, or used as a part |
| `unused_pub_dependency` | Declared packages with no recognized source, analyzer configuration, native plugin, or font asset use |
| `test_only_used` | Library declarations referenced only by tests |
| `unused_parameter` | Parameters never read by their declaration |
| `unused_parameter_optional` | Optional parameters never passed at any call site |

## Tool comparison

| Feature | **kareki** | [ciach](https://github.com/leancodepl/ciach) | [Dart Code Linter](https://github.com/bancolombia/dart-code-linter) | [dependency_validator](https://github.com/Workiva/dependency_validator) | [Dart standard analysis](https://dart.dev/tools/diagnostics/unused_element) |
|---|:---:|:---:|:---:|:---:|:---:|
| [Detect unused public declarations and members](comparison.md#unused-public-declarations-and-members) | ✅ | ✅ | ✅ | — | — |
| [Detect unused private declarations and members](comparison.md#unused-private-declarations-and-members) | ✅ | ✅ | ✅ | — | ✅ |
| [Detect unused values of public enums](comparison.md#unused-public-enum-values) | ✅ | ✅ | ✅ | — | — |
| [Detect cycles of public declarations unreachable from entry points](comparison.md#public-declaration-cycles-unreachable-from-entry-points) | ✅ | — | — | — | — |
| [Detect unused Dart files](comparison.md#unused-dart-files) | ✅ | — | ✅ | — | — |
| [Detect unused pub dependencies](comparison.md#unused-pub-dependencies) | ✅ | — | — | ✅ | — |
| [Detect optional public API parameters never supplied by callers](comparison.md#optional-public-api-parameters-never-supplied-by-callers) | ✅ | — | — | — | — |
| [Detect public declarations used only by tests](comparison.md#public-declarations-used-only-by-tests) | ✅ | — | — | — | — |
| [Dedicated unused-l10n checks](comparison.md#unused-localization-keys) | ✅ | — | ✅ | — | — |
| [Report only new findings using a baseline](comparison.md#report-only-new-findings-using-a-baseline) | ✅ | — | — | — | — |
| [Check stale exclusions and baseline entries](comparison.md#stale-exclusions-and-baseline-entries) | ✅ | — | — | — | — |
| Automatically remove unused public declarations | Not planned | ✅ | — | — | — |

See the [comparison details](comparison.md) for required settings, limitations, and versions compared.

## Explore the documentation

- [CLI reference](cli/) — commands, options, formats, and exit codes
- [Configuration](configuration/) — workspace settings, presets, exclusions, and suppressions
- [Baseline](baseline/) — adopt kareki incrementally in an existing codebase
- [Doctor](doctor/) — detect stale exclusions and suppressions
- [How it works](how-it-works/) — understand the analysis pipeline and its boundaries
- [Comparing similar tools](comparison/) — ciach, Dart Code Linter, and other Dart tools
- [Best practices](operations/) — schedule cleanup pull requests with an AI agent

## Links

- [GitHub](https://github.com/ostk0069/kareki) — source code and issue tracker
- [pub.dev](https://pub.dev/packages/kareki) — package releases
- [Changelog](https://github.com/ostk0069/kareki/blob/main/CHANGELOG.md) — release history
