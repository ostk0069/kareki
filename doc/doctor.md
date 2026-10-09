---
title: Doctor
weight: 5
---

`kareki doctor` finds configuration that no longer applies: unmatched file
patterns, missing packages, ineffective suppression comments, and stale baseline
entries. It reports issues without modifying files.

```sh
dart run kareki doctor
```

## Checks

| Issue kind | Meaning |
|---|---|
| `unused-exclude` | An `exclude.files` entry matches no workspace `.dart` file. |
| `unused-exclude-parameter-name` | An `exclude.parameter_names` entry suppresses no current `unused_parameter` or `unused_parameter_optional` finding. |
| `unused-ignore-package` | An `ignore.packages` entry names no workspace package. |
| `unused-ignore-dependencies-package` | An `ignore.dependencies` key names no workspace package. |
| `unused-ignore-dependency` | An ignored dependency is not declared in that package's `pubspec.yaml`. |
| `unused-ignore-directive` | A file-level or per-line suppression comment suppresses no finding. Per-line comments report the targeted line as `<path>:<line>`. |
| `unused-baseline-entry` | A baseline entry no longer matches a current finding. The code may have been removed, moved, or become used. |

Only user-supplied entries are checked. Built-in defaults, such as the
`**/*.g.dart` exclusion, are not flagged.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | All checks completed with no issues. |
| `1` | All checks completed with at least one issue. |
| `2` | Analysis failed or warnings prevented safe completion. Takes precedence over `1`. |
| `64` | Invalid CLI options or kareki configuration. |

## When checks cannot complete

Doctor uses resolved references to check parameter-name exclusions, suppression
comments, and baseline entries. It shares one source snapshot across these checks.

If source resolution or gen-l10n input loading fails, doctor returns `2` without
a report. If analysis warnings leave usage uncertain, it skips these
usage-dependent checks, explains why on stderr, and returns `2`.
Structural checks, such as unmatched file patterns,
can still produce issues.

An empty JSON array with exit code `2` does **not** mean the configuration is
clean. Do not remove suppressions or baseline entries based on that empty result.
See [how it works](how-it-works.md#reviewing-the-results) for examples and guidance on reviewing the results.

Library users must await `DoctorRunner().analyze(request)` or `run(request)`.
See the [API example and notes](https://github.com/ostk0069/kareki/blob/main/example/example.md#programmatic-api).
