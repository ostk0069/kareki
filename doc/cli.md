---
title: CLI reference
weight: 2
---

Run from the workspace root:

```sh
dart run kareki
```

## Preparation

Use the project's SDK to install dependencies (`dart pub get`, `flutter pub get`,
or workspace bootstrap), then run code generation. Generated and excluded files
still contribute references and must resolve.

## Options

| Option | Description |
|---|---|
| `--root <path>` | Workspace root. Defaults to the current directory. |
| `-f`, `--format <name>` | Output format: `text` or `json`. Overrides configuration. |
| `--packages <name>` | Report findings only for these packages. References are still collected across the discovered workspace. Repeatable. |
| `--rule <id>` | Enable only these rules. Repeatable. |
| `--strict` | Include `dev_dependencies` in `unused_pub_dependency` checks. |
| `--baseline <path>` | Hide findings recorded in this baseline. Overrides the configured `baseline` path. |
| `--write-baseline` | Save current findings and exit. Requires a baseline path in options or configuration. |
| `-h`, `--help` | Show usage. |

For example, to run only the declaration-identity rules:

```sh
dart run kareki --rule unused_element,test_only_used,unused_parameter_optional
```

Like `--packages`, `ignore.packages` suppresses reports without hiding consumers.
By contrast, `packages.exclude` excludes packages from discovery.
See [configuration](configuration.md).

## Results and exit codes

| Code | Meaning |
|---|---|
| `0` | No findings remain after filtering, or a baseline was successfully written. |
| `1` | One or more findings remain after filtering. |
| `2` | Resolution failed. No findings or baseline are published. |
| `64` | Invalid options or configuration. |

Analysis warnings describe uncertain usage, not confirmed unused code.
They go to **stderr**, separately from text or JSON findings, and have no rule ID
or dedicated exit code. Warnings alone do not cause a nonzero exit:
a normal run can return `0` with warnings. They also do not prevent
`--write-baseline` from saving findings, so review stderr before accepting a baseline.

`kareki doctor` is stricter: warnings prevent safe suppression and baseline
cleanup checks, so it returns `2`. See [doctor](doctor.md).

When upgrading from name-based analysis, review newly exposed findings before
updating your baseline. See the [migration guide](migration.md).
