# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.4.0

### Added

- Japanese translations of the README and every page under `docs/`
  (`README.ja.md`, `docs/*.ja.md`). Each English page now links to its
  Japanese counterpart and vice versa. *(Retroactive entry for #5,
  which was merged without a changelog update.)*
- New rule `unused_parameter`: flags parameters declared by a function,
  method, or named constructor that are never referenced in the body or
  initializers. Covers required and optional parameters, public and
  private — a strict superset of Dart's built-in
  `unused_element_parameter` (which only flags private optional
  parameters never passed at a call site). Skips `@override`, abstract /
  external / native callables, operators, `this.x` / `super.x`, the
  `_` / `__` placeholder convention, any declaration kept alive by a
  configured keep-alive annotation, and stub bodies whose only
  statement is `throw UnimplementedError(...)` (federated plugin
  `PlatformInterface` base methods). Callback functions whose
  signature is constrained by a typedef (e.g. auto_route
  `CustomRouteBuilder` / `AutoRouteGroup` conformers) are intentionally
  still flagged so the unused parameter is surfaced — rename to `_` to
  preserve typedef conformance while signaling intent. Suppress
  remaining cases via `// kareki: ignore_for_file=unused_parameter` or
  `ignore.rules: [unused_parameter]` in `kareki-config.yaml`.

### Changed

- Top-level `README.md` has been split into focused pages under
  `docs/` (CLI reference, configuration, baseline, doctor, how-it-works).
  The root README now serves as a short overview with links into the
  detailed docs. *(Retroactive entry for #5.)*

## 0.3.0

### Added

- Baseline support — adopt kareki on an existing codebase without first
  resolving every finding. `dart run kareki --baseline <path>
  --write-baseline` snapshots the current findings to a JSON file;
  subsequent runs that point at the same baseline (either via
  `--baseline` or `baseline:` in `kareki-config.yaml`) suppress those
  findings from the output and the exit code, while any new finding
  still fails the run. The baseline file uses a `<root>/` placeholder
  for the workspace path embedded in each `stableId`, so it is portable
  across machines and CI checkouts. Entries are sorted by
  `(ruleId, stableId)` for clean diffs.
- `kareki doctor` now reports `unused-baseline-entry` for any baseline
  entry whose `(ruleId, stableId)` no longer matches a current finding
  — the suppressed dead code has been deleted or relocated and the
  baseline is ready to be regenerated.

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
