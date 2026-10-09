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
  kareki: ^0.7.0
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

Six key features at a glance. ✅ Supported (including opt-in features), — no equivalent feature.

| Feature | **kareki** | ciach | Dart Code Linter | dependency_validator | Dart standard analysis |
|---|:---:|:---:|:---:|:---:|:---:|
| [Unused public declarations and members](how-it-works.md#analysis-flow) | ✅ | ✅ | ✅ | — | — |
| Unused private declarations and members | — | ✅ | ✅ | — | ✅ |
| [Public declaration cycles unreachable from entry points](comparison.md#analysis-differences) | ✅ | — | — | — | — |
| [Unused Dart files](how-it-works.md#evidence-used-by-each-rule) | ✅ | — | ✅ | — | — |
| [Unused pub dependencies](configuration.md#dependency-usage-beyond-imports) | ✅ | — | — | ✅ | — |
| [Report only new findings using a baseline](baseline.md) | ✅ | — | — | — | — |

See the [full comparison](comparison.md) for other features, required settings, limitations, and versions compared.

## Explore the documentation

- [CLI reference](cli/) — commands, options, formats, and exit codes
- [Configuration](configuration/) — workspace settings, presets, exclusions, and suppressions
- [Baseline](baseline/) — adopt kareki incrementally in an existing codebase
- [Doctor](doctor/) — detect stale exclusions and suppressions
- [How it works](how-it-works/) — understand the analysis pipeline and its boundaries
- [Comparing similar tools](comparison/) — choose between kareki, ciach, and other Dart tools
- [Best practices](operations/) — schedule cleanup pull requests with an AI agent

## Links

- [GitHub](https://github.com/ostk0069/kareki) — source code and issue tracker
- [pub.dev](https://pub.dev/packages/kareki) — package releases
- [Changelog](https://github.com/ostk0069/kareki/blob/main/CHANGELOG.md) — release history
