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
| `unused_element` | Public classes / functions / methods / getters / setters / fields / top-level variables / extensions / typedefs with no caller anywhere in the workspace. |
| `unused_file` | `.dart` files that are not `import`-ed, `part`-ed, or `export`-ed from any other file. |
| `unused_pub_dependency` | Packages declared in `pubspec.yaml` whose imports never appear in source. |
| `test_only_used` | Public declarations under `lib/` that are only referenced from test code (`*_test.dart`, files under `test/` or `integration_test/`). The implementation has no production consumer — typically its tests are the only thing keeping it alive. |

## Install

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

See [docs/cli.md](docs/cli.md) for all options.

## Adopting on an existing codebase

Don't try to delete every finding before turning on CI. Snapshot what's there, commit it, fail only on **new** dead code from now on:

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

See [docs/baseline.md](docs/baseline.md).

## Keeping the config honest

Once you start excluding files or whitelisting dependencies, the list rots — packages move, files get renamed, the excludes still pass. `kareki doctor` finds dead entries in your own config:

```sh
dart run kareki doctor
```

See [docs/doctor.md](docs/doctor.md).

## Documentation

- [CLI reference](docs/cli.md) — every option, every exit code
- [Configuration](docs/configuration.md) — `kareki-config.yaml`, defaults, built-in presets, custom presets, suppression, full example
- [Baseline](docs/baseline.md) — incremental adoption
- [Doctor](docs/doctor.md) — config-rot detection
- [How it works](docs/how-it-works.md) — analysis pipeline, entry-point seeding, supported versions

## License

MIT. See [LICENSE](LICENSE).
