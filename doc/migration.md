---
title: Migrating from name-based analysis
weight: 8
---

The next release uses analyzer-resolved declaration identities for reachability
and optional-argument checks. The old engine and its mode switch are removed.
Resolution errors do not fall back to the old engine.

## CLI migration

1. Use the project's SDK to install dependencies and generate sources.
   Generated and excluded files still contribute references and must resolve.
   The SDK and analyzer must support the project's language features; parser-only
   support for experimental syntax is not enough.
2. Remove `analysis_mode` from configuration and `--analysis-mode` from scripts.
   Obsolete options return exit code `64`.
3. Run kareki and review findings before updating the baseline. Baseline IDs and
   JSON formats are unchanged, but separating same-name declarations can expose
   new findings. Package filters limit reports, not reference collection.
4. Run `dart run kareki doctor` before removing old suppressions. Exit code `2`
   means checks could not complete safely, not that the configuration is clean.

Resolution failures produce no partial findings and do not overwrite baselines.
Analysis warnings are different: they retain potentially used code but do not
fail a normal run. See [CLI exit codes](cli.md) and [doctor](doctor.md).

## Library API migration

Await runner and CLI APIs:

```dart
final result = await KarekiRunner().analyze(request);
// run(request) is also asynchronous.
```

- `KarekiRunner.run`, `KarekiRunner.analyze`, `DoctorRunner.run`, and
  `DoctorRunner.analyze` return Futures.
- `runCli` and `runDoctor` also return Futures. The preview names
  `runCliAsync` and `runDoctorAsync` are removed.
- `AnalysisMode` and its arguments are removed.
- Legacy name-reference metadata on `ParsedFile`, `DeclarationRecord`,
  and `EntryPointSet` is removed.

## Comparing performance

Resolved analysis requires more work than name matching. To measure the change,
run `tool/resolved_analysis/benchmark.dart ROOT [doctor]` with the same SDK,
source snapshot, configuration, and rules. Compare multiple fresh-process runs
and peak memory (RSS), keeping source changes separate from engine changes.

There is no persistent analysis cache; each invocation reads current sources.
Rules that do not require resolution can still run without dependency setup.
See [analysis internals](analysis-internals.md) for reuse within a single run.
