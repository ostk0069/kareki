# kareki

**English** | [日本語](README.ja.md)

<img width="1645" height="496" alt="header image" src="https://github.com/user-attachments/assets/dc3b1903-8ff1-4556-9d4e-ac847e3c8bd0" />

[![pub package](https://img.shields.io/pub/v/kareki.svg)](https://pub.dev/packages/kareki)
[![CI](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml/badge.svg)](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

> 枯木 (kareki): dead wood in Japanese — the unused branches that need pruning.

A **workspace-wide dead code finder for Dart and Flutter**. Unlike `dart analyze`, which only flags private unused declarations inside a single package, `kareki` resolves cross-package references across Melos / pub workspaces to surface the dead code that actually accumulates in real projects: public APIs no one calls, files nobody imports, and pub dependencies that ride along unused.

## Why kareki?

|  | What you get |
|---|---|
| 🌲 | **Workspace-wide.** Resolves references across every package in Melos / pub workspaces — not just one. |
| 🔓 | **Public APIs too.** Finds the public classes, methods, and fields `dart analyze` ignores. |
| 🧬 | **Codegen-friendly.** Built-in presets for freezed, json_serializable, riverpod, auto_route, go_router, drift, hive. |
| 🧪 | **`test_only_used`.** Catches `lib/` code that only its own tests still use. |
| 📉 | **Baseline.** Adopt on legacy code without fixing everything first — CI fails only on *new* findings. |
| 🩺 | **Doctor.** `kareki doctor` flags stale `ignore` entries, dead excludes, and orphan suppression comments. |
| ⚙️ | **CI-ready.** JSON output, deterministic exit codes, portable baselines. |

## What it finds

| Rule | Detects |
|---|---|
| `unused_element` | Public classes / functions / methods / getters / setters / fields / top-level variables / extensions / extension types / typedefs with no caller anywhere in the workspace. |
| `unused_file` | `.dart` files that are not `import`-ed, `part`-ed, or `export`-ed from any other file. |
| `unused_pub_dependency` | Packages declared in `pubspec.yaml` with no recognized source, analyzer configuration, native plugin, or font asset use. |
| `test_only_used` | Public declarations under `lib/` that are only referenced from test code (`*_test.dart`, files under `test/` or `integration_test/`). The implementation has no production consumer — typically its tests are the only thing keeping it alive. |
| `unused_parameter` | Parameters of a function, method, or named constructor that are never referenced in the body or initializers. Covers required and public-API parameters that Dart's built-in `unused_element_parameter` doesn't reach. |
| `unused_parameter_optional` | Optional parameters (named or positional optional) of a function, method, or constructor that are never passed at any call site in the workspace. The public / cross-package counterpart to Dart's built-in `unused_element_parameter`, which only inspects private optional parameters within a single library. |

## Install

```yaml
# pubspec.yaml
dev_dependencies:
  kareki: ^0.7.0
```

```sh
dart pub get
```

## Usage

Install the project's dependencies and run code generation, then execute from
the workspace root:

```sh
dart run kareki
```

See the [CLI reference](doc/cli.md) for preparation, options, and analysis warnings.

## Adopting on an existing codebase

You can adopt kareki without fixing all existing findings. Review the results,
save them as a baseline, and commit it so CI reports only new findings:

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

See [doc/baseline.md](doc/baseline.md).

## Keeping the config honest

File moves and dependency changes can leave obsolete exclusions and suppressions.
`kareki doctor` checks which entries no longer apply:

```sh
dart run kareki doctor
```

See [doc/doctor.md](doc/doctor.md).

## Documentation

Browse the [documentation site](https://ostk0069.github.io/kareki/) or read the Markdown sources directly:

- [CLI reference](doc/cli.md) — every option, every exit code
- [Configuration](doc/configuration.md) — `kareki-config.yaml`, defaults, built-in presets, custom presets, suppression, full example
- [Baseline](doc/baseline.md) — incremental adoption
- [Doctor](doc/doctor.md) — obsolete exclusions and suppressions
- [How it works](doc/how-it-works.md) — analysis flow, entry points, limits, and supported versions
- [Comparing similar tools](doc/comparison.md) — kareki, ciach, and other Dart tools
- [Best practices](doc/operations.md) — scheduled cleanup pull requests with an AI agent

## License

MIT. See [LICENSE](LICENSE).
