# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0

### Added

- New `kareki doctor` subcommand: validates `kareki-config.yaml` against
  the workspace and reports stale `exclude.files` globs, `ignore.packages`
  / `ignore.dependencies` entries pointing at packages or deps that no
  longer exist, and `// kareki: ignore_for_file=<rule>` directives that
  suppress no actual finding. Only user-supplied entries are checked —
  built-in defaults are never flagged. `text` and `json` output formats
  are supported via `--format`.

### Fixed

- `// kareki: ignore_for_file=<rule>` was silently no-op when the
  directive line was followed by a blank line and an `import` statement
  (instead of another comment line). The regex used `\s` inside the rule
  capture, which let `\n` and subsequent source characters bleed into
  the captured value until a non-`\w`/`\s` character (typically the
  string quote in the next `import 'package:...';`) was reached;
  comma-split + trim then produced corrupted tokens that never matched
  any real rule id. The capture now stops at end-of-line.

## 0.1.1

### Added

- New rule `test_only_used`: flags public declarations under `lib/` that are
  only reachable from test entry points (`*_test.dart`, `test/`,
  `integration_test/`). Detects the "code that exists only because its tests
  exist" anti-pattern that the standard reachability analysis misses because
  test files are themselves entry points.
- `EntryPointSet` now exposes `productionRootNames` / `testRootNames` for
  callers that need to distinguish production vs test consumption.
- `ReachabilityBfs.compute` accepts an optional `filter` callback so callers
  can constrain BFS traversal (used by `test_only_used` to keep production
  BFS from crossing into test source via shared simple names like `main`).

## 0.1.0

Initial release.

- Rules: `unused_element`, `unused_file`, `unused_pub_dependency`.
- Multi-package workspaces via `melos.yaml` / pub workspaces.
- Built-in presets: `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta`.
- Configuration via `kareki-config.yaml` with full override and custom preset support.
- CLI: `dart run kareki` with `--format`, `--packages`, `--rule`, `--strict`.
- Dart `>=3.10.0`, analyzer `^9.0.0`.
