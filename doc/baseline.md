---
title: Baseline
weight: 4
---

A baseline records existing findings so you can adopt kareki without fixing them
all first. Later runs report only findings that are not in the baseline.

## Create a baseline

From a clean working tree, install dependencies, generate sources, and review
kareki's findings and analysis warnings. Then save the findings:

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

Commit `.kareki-baseline.json`. To use it on later runs, pass
`--baseline .kareki-baseline.json` or set this in `kareki-config.yaml`:

```yaml
baseline: .kareki-baseline.json
```

Matching findings are omitted from output and do not cause exit code `1`.
New findings still do. Saving a baseline returns `0`; analysis warnings can
still be present on stderr. See [CLI exit codes](cli.md).

## Update a baseline

After reviewing fixes and new findings, run the same save command again.
Always supply the path, either through `--baseline` or configuration.
Use [doctor](doctor.md) to check for stale entries before removing them.

Entries are sorted by `(ruleId, stableId)` for readable diffs. Absolute workspace
paths in `stableId` are replaced with `<root>/`, so the file can be shared across
machines and CI checkouts.
