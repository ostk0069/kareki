# Doctor

**English** | [日本語](doctor.ja.md)

`kareki doctor` validates `kareki-config.yaml` against the actual state of your workspace. It surfaces configuration that no longer matches reality — globs that match no file, `ignore.*` entries pointing at packages or dependencies that have been removed, and inline `// kareki: ignore_for_file=...` / `// kareki: ignore=...` directives that suppress nothing.

```sh
dart run kareki doctor
```

| Issue kind | Meaning |
|---|---|
| `unused-exclude` | An entry in `exclude.files` matched no `.dart` file in the workspace. |
| `unused-ignore-package` | A name in `ignore.packages` is not a package in the workspace. |
| `unused-ignore-dependencies-package` | A key in `ignore.dependencies` is not a package in the workspace. |
| `unused-ignore-dependency` | A value listed under `ignore.dependencies.<pkg>` is not declared in that package's `pubspec.yaml`. |
| `unused-ignore-directive` | A `// kareki: ignore_for_file=<rule>` or `// kareki: ignore=<rule>` directive suppresses no actual finding. Per-line directives report the targeted line as `<path>:<line>`. |
| `unused-baseline-entry` | An entry in the baseline file no longer matches any current finding — the suppressed dead code has been removed or relocated. |

Only **user-supplied** entries are checked. Built-in defaults (e.g. the bundled `**/*.g.dart` exclude) are never flagged.

Exits `0` when the configuration is clean, `1` when at least one issue is reported.
