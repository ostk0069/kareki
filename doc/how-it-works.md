---
title: How it works
weight: 6
---

Kareki follows references across a Dart / Flutter workspace to find code that
has no recognized use. Declarations with the same name are tracked separately.

## Analysis flow

1. Discover packages through `melos.yaml`, pub workspace, or configuration.
2. Collect Dart sources, declarations, and suppression comments.
3. Identify entry points: code treated as used without a caller.
4. Resolve references with analyzer and follow them from those entry points.
5. Report unreachable declarations, unreferenced files, and declared pub
   dependencies with no recognized use.

Package filters such as `--packages` limit reports, not reference collection.
See [configuration](configuration.md) for source directories and discovery settings.

## Entry points

Four sources provide entry points:

| Source | Examples |
|---|---|
| Dart / Flutter conventions | Top-level `main`, test files, `bin/`, `integration_test/`, `lib/l10n/`, and `flutter_test_config.dart`. |
| Configuration | `entry_points.files` and `entry_points.names`; default file patterns cover stories and widgetbook. |
| Annotations | Built-in and custom presets, plus `keep_alive_annotations.custom`. |
| Generated or excluded files | Their declarations and outgoing references remain part of the graph, although the files are not reported as unused. |

Generated code can therefore keep its source declarations in use. Run code
generation before analysis; kareki does not generate missing files.

## Same-name declarations and optional arguments

References are tied to individual declarations, not just names. Calling
`A.load()` does not by itself keep an unrelated `B.load()` alive.
Explicit `entry_points.names` settings still match by name.

Optional-argument checks collect calls from all scanned sources, including
generated and unreachable code. Usage also follows actual overrides and
redirecting factories. Each optional parameter is classified as:

| State | Meaning |
|---|---|
| Used | A known call supplies the argument, or modeled usage requires retaining it. |
| Unused within scope | No scanned call supplies it and no unknown call path remains. It may be reported. |
| Unknown | A call path cannot be checked safely. The parameter is not reported as unused. |

Valid top-level `main` positional parameters can be supplied by the runtime.
This does not exempt them from the separate check for unused parameters inside
the function body.

## What the results do not guarantee

Dynamic calls, callbacks, and conditional imports can leave usage uncertain.
Kareki retains code that might be used and emits analysis warnings where needed.
Warnings are separate from unused-code findings; see the
[CLI reference](cli.md) for output and exit codes.

Findings apply to the sources and build configuration that were analyzed.
They do not establish whether an external application uses a public API, or
guarantee runtime behavior on every platform. If build scripts replace sources
for different variants, prepare and analyze each variant or explicitly retain
its entry files. Kareki does not run those scripts.

Before deleting code, review the finding and any warnings. After deletion,
regenerate sources and run the project's analysis, tests, and relevant builds.

## Supported versions

| Component | Version |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `>=10.2.0 <15.0.0` |

CI runs analysis and tests against every supported Dart minor version and the
latest stable SDK patch.

For the safety principles behind the analysis, see
[analysis internals](analysis-internals.md).
