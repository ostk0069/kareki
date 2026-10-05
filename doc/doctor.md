---
title: Doctor
weight: 5
---

`kareki doctor` validates `kareki-config.yaml` against the actual state of your workspace. It surfaces configuration that no longer matches reality — globs and parameter-name excludes that suppress nothing, `ignore.*` entries pointing at packages or dependencies that have been removed, and ineffective inline `// kareki: ignore_for_file=...` / `// kareki: ignore=...` directives.

```sh
dart run kareki doctor
```

| Issue kind | Meaning |
|---|---|
| `unused-exclude` | An entry in `exclude.files` matched no `.dart` file in the workspace. |
| `unused-exclude-parameter-name` | A name in `exclude.parameter_names` suppresses no current `unused_parameter` or `unused_parameter_optional` finding. |
| `unused-ignore-package` | A name in `ignore.packages` is not a package in the workspace. |
| `unused-ignore-dependencies-package` | A key in `ignore.dependencies` is not a package in the workspace. |
| `unused-ignore-dependency` | A value listed under `ignore.dependencies.<pkg>` is not declared in that package's `pubspec.yaml`. |
| `unused-ignore-directive` | A `// kareki: ignore_for_file=<rule>` or `// kareki: ignore=<rule>` directive suppresses no actual finding. Per-line directives report the targeted line as `<path>:<line>`. |
| `unused-baseline-entry` | An entry in the baseline file no longer matches any current finding — the suppressed dead code has been removed or relocated. |

Only **user-supplied** entries are checked. Built-in defaults (e.g. the bundled `**/*.g.dart` exclude) are never flagged.

Exits `0` when the configuration is clean, `1` when at least one issue is reported.

## Resolved analysis (preview)

```sh
dart run kareki doctor --analysis-mode resolved
```

The flag overrides `analysis_mode` in config; the default remains `legacy`.
Use the same mode that generated your baseline. Baseline IDs and report JSON
formats are unchanged, and doctor does not modify files.

All semantic checks (parameter exclusions, inline directives, stale baseline
entries) use the selected engine. Resolution failures return exit code `2`
without a report. If conservative approximations are necessary (e.g. callbacks
or dynamic calls), doctor skips these semantic checks, warns on stderr and
returns `2`; structural checks such as unmatched globs can still be reported.
An empty JSON findings array with exit code `2` does **not** mean healthy.
Invalid options/config return `64`.

Programmatic users can call `await DoctorRunner().analyze(request)` with
`analysisMode: AnalysisMode.resolved`. Synchronous `run()` remains legacy-only.
