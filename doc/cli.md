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

## Resolved analysis

After running `pub get` / workspace bootstrap and code generation:

```sh
dart run kareki --rule unused_element,test_only_used,unused_parameter_optional
```

Reachability and optional-argument usage are resolved by declaration identity.
Other rules retain their existing algorithms. `--packages` limits reports,
not reference collection; `ignore.packages` also suppresses reports without
hiding consumers. Discovery-level `packages.exclude` still excludes packages.
Generated/excluded files still contribute references and must resolve.

Resolution errors are written to stderr and exit with 2. Approximation warnings
are also written to stderr, leaving text/JSON findings unchanged.
Existing baselines remain readable; new findings can appear because homonyms
no longer mask unused declarations. Review the difference before accepting it.

Use `dart run kareki doctor` to check suppressions and
baselines with the same engine. The legacy engine and mode options have been removed.
Doctor exits with 2 if resolution fails or approximation warnings prevent safe
semantic checks. Review newly exposed findings before updating existing baselines. See [doctor](doctor.md).
