# Baseline

**English** | [日本語](baseline.ja.md)

A baseline lets you adopt kareki on a large codebase without first deleting every existing finding: snapshot the current state, commit the snapshot, and the CI only fails on **new** findings going forward.

Generate the baseline from a clean working tree:

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

This writes every current finding to `.kareki-baseline.json`. Commit the file. Subsequent runs that point at the same baseline (either via `--baseline` or `baseline: .kareki-baseline.json` in `kareki-config.yaml`) suppress matching findings from the output and the exit code, while any new finding still fails the run.

The file is sorted by `(ruleId, stableId)` so it produces clean diffs, and absolute workspace paths embedded in `stableId` are replaced with `<root>/` so the baseline is portable across machines and CI checkouts.

To shrink the baseline as findings get fixed, just regenerate it: `dart run kareki --write-baseline`.
