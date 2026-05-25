# CLI reference

**English** | [日本語](cli.ja.md)

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
| `64` | Invalid CLI usage. |
