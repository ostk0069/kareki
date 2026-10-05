---
title: CLI reference
weight: 2
---

Run from the workspace root:

```sh
dart run kareki
```

## Options

| Option | Description |
|---|---|
| `--root <path>` | Workspace root. Defaults to the current directory. |
| `--analysis-mode <mode>` | `legacy` (default) or experimental `resolved`. Overrides `analysis_mode` in config. |
| `-f`, `--format <name>` | Output format: `text` \| `json`. Overrides `kareki-config.yaml`. |
| `--packages <name>` | Restrict analysis to these packages. Repeatable. |
| `--rule <id>` | Enable only these rules. Repeatable. |
| `--strict` | Treat `dev_dependencies` the same as `dependencies` for `unused_pub_dependency`. |
| `--baseline <path>` | Path to a baseline file. Findings present in the baseline are hidden from output. Overrides `baseline:` in `kareki-config.yaml`. |
| `--write-baseline` | Write the current findings to the baseline file and exit. Requires `--baseline <path>` or `baseline:` in config. |
| `-h`, `--help` | Show usage. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | No findings. |
| `1` | One or more findings reported. |
| `2` | Resolved analysis could not complete. No findings or baseline are published. |
| `64` | Invalid CLI usage. |

## Experimental resolved analysis

After running `pub get` / workspace bootstrap and code generation:

```sh
dart run kareki --analysis-mode resolved --rule unused_element,test_only_used,unused_parameter_optional
```

This preview changes `unused_element`, `test_only_used`, and `unused_parameter_optional`. Other rules
retain their existing algorithms. In resolved mode `--packages` limits reports,
not reference collection; `ignore.packages` also suppresses reports without
hiding consumers. Discovery-level `packages.exclude` still excludes packages.
Generated/excluded files still contribute references and must resolve.

Resolution errors are written to stderr and exit with 2. Approximation warnings
are also written to stderr, leaving text/JSON findings unchanged.
Existing baselines remain readable; new findings can appear because homonyms
no longer mask unused declarations. Review the difference before accepting it.

Use `dart run kareki doctor --analysis-mode resolved` to check suppressions and
baselines with the same engine. Both commands also honor `analysis_mode` in config.
Doctor exits with 2 if resolution fails or approximation warnings prevent safe
semantic checks. Do not use legacy doctor's stale-finding checks to prune a
baseline generated with resolved analysis. See [doctor](doctor.md).
