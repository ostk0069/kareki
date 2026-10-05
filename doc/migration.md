---
title: Migrating from name-based analysis
weight: 8
---

The next release removes the legacy engine. All reachability and optional-call
argument decisions use analyzer-resolved declaration identities; there is no
name-based fallback or mode switch.

1. Run `dart pub get`, `flutter pub get`, or your workspace bootstrap with the
   project's SDK, then run its normal code-generation commands. Generated and
   excluded sources still contribute references and must resolve.
   Use an SDK/analyzer combination supporting the target language version.
   Parser-only support for an experimental syntax is not sufficient for resolved
   analysis; unsupported language features fail closed instead of producing findings.
2. Remove `analysis_mode` from configuration and `--analysis-mode` from scripts.
   Obsolete options are rejected with exit code 64 rather than silently ignored.
3. Run kareki and review findings before updating baselines. Baseline identities
   and JSON formats are unchanged, but previously conflated declarations can now
   produce additional findings. Package filters limit reports, not consumers.
4. Await library APIs: `await KarekiRunner().run(request)` (or `.analyze`) and
   `await DoctorRunner().run(request)` (or `.analyze`). `runCli` and `runDoctor`
   also return Futures. The preview's `runCliAsync` / `runDoctorAsync` names and
   `AnalysisMode` arguments are removed. Low-level name-reference metadata on
   `ParsedFile`, `DeclarationRecord`, and `EntryPointSet` is removed as well.
5. Run `kareki doctor` before pruning old suppressions. Doctor resolves the source
   once and shares it across its checks. Resolution failure or uncertainty that
   prevents safe cleanup returns 2, not a healthy result.

Resolution failure aborts graph-based analysis without publishing partial
findings or overwriting a baseline. Uncertainty warnings retain conservative
protection; they are distinct from unused-code findings. Rules that do not need
the resolved graph can run without bootstrap. No persistent analysis cache is
used, so a subsequent invocation always observes current sources.

Resolved analysis costs more time and memory than name matching. The benchmark
tool accepts `ROOT [doctor]`; compare the same SDK, source snapshot, configuration,
and rule set in fresh processes. Report multiple runs and peak RSS, and keep
source changes separate from engine performance changes.
