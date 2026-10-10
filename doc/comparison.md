---
title: Comparing similar tools
weight: 8
---

Kareki focuses on workspace-wide unused code detection and ongoing cleanup in CI.

## Feature comparison

✅ Supported (including opt-in features), △ partially supported, — no equivalent feature.

| Feature | **kareki** | [ciach][ciach-repo] | [Dart Code Linter][dcl-repo] | [dependency_validator][dependency-repo] | [Dart standard analysis][dart-unused] |
|---|:---:|:---:|:---:|:---:|:---:|
| [Detect unused public declarations and members](#unused-public-declarations) | ✅ | ✅ | ✅ | — | — |
| Detect unused private declarations and members | — | ✅ | ✅ | — | ✅ |
| [Detect unused values of public enums](#unused-enum-values) | ✅ | ✅ | ✅ | — | — |
| [Detect cycles of public declarations unreachable from entry points](#unreachable-cycles) | ✅ | — | — | — | — |
| [Detect unused Dart files](#unused-dart-files) | ✅ | — | ✅ | — | — |
| [Detect unused pub dependencies](#unused-pub-dependencies) | ✅ | — | — | ✅ | — |
| [Detect optional public API parameters never supplied by callers](#unsupplied-optional-parameters) | ✅ | — | — | — | — |
| [Detect public declarations used only by tests](#test-only-declarations) | ✅ | — | — | — | — |
| Dedicated unused-l10n checks | Coming soon | — | ✅ | — | — |
| [Report only new findings using a baseline](#baseline) | ✅ | — | — | — | — |
| [Check stale exclusions and baseline entries](#stale-configuration) | ✅ | — | — | — | — |
| Automatically remove unused public declarations | Coming soon | △ | — | — | — |

- A ✅ still has analysis limits; for example, kareki excludes operators.
- Enum values are compared separately from declarations and members.
- Dart Code Linter's public / private member checks require opt-in flags and include enum values.
  See its [CLI][dcl-cli].
- Dart Code Linter's l10n check targets members of Dart classes. The default class-name
  pattern is `I18n$`; use `--class-pattern AppLocalizations` for `AppLocalizations`.
  See its [configuration][dcl-l10n].
- Some ciach findings are report-only and cannot be automatically removed.
  See its [README][ciach-readme].
- The parameter row checks whether callers supply values. This differs from
  Dart Code Linter's [unused-in-body check][dcl-parameters] and
  Dart's [check for private declarations][dart-parameter].

## Feature details

### Unused public declarations and members {#unused-public-declarations}

Find public classes, functions, fields, and methods that have no recognized use
within the analyzed workspace. Kareki reports eligible declarations that cannot
be reached from entry points with `unused_element`.
See the [analysis example](how-it-works.md#analysis-flow).

### Unused public enum values {#unused-enum-values}

Check individual enum values, even when the enum type itself is used. For example,
if only `Status.active` is used, `Status.archived` may be unused. Kareki checks
values with `unused_element`; a reachable `Status.values` retains every value.
See [rule evidence](how-it-works.md#evidence-used-by-each-rule).

### Public declaration cycles unreachable from entry points {#unreachable-cycles}

Find public declarations that reference each other but cannot be reached from
entry points such as `main`. A reference within the cycle alone does not make
those declarations used in kareki.
See [analysis differences](#analysis-differences).

### Unused Dart files {#unused-dart-files}

Find Dart files that no other scanned file imports, exports, or includes with
`part`, and that are not entry-point files. Kareki's `unused_file` checks file
references separately from whether the declarations inside are reachable.
See [rule evidence](how-it-works.md#evidence-used-by-each-rule).

### Unused pub dependencies {#unused-pub-dependencies}

Find dependencies declared in `pubspec.yaml` that have no recognized use.
Kareki's `unused_pub_dependency` also recognizes supported annotation,
build-configuration, native-plugin, and asset usage, beyond Dart imports.
See [dependency usage beyond imports](configuration.md#dependency-usage-beyond-imports).

### Optional public API parameters never supplied by callers {#unsupplied-optional-parameters}

Find optional named or positional parameters for which no scanned caller supplies
a value. This can reveal an API option that is never exercised, even when the
function body reads the parameter's default value. Kareki's
`unused_parameter_optional` does not report parameters with unknown call paths.
See [optional-argument usage](how-it-works.md#optional-argument-usage).

### Public declarations used only by tests {#test-only-declarations}

Find public declarations reachable from test entry points but not production
entry points. Kareki's `test_only_used` distinguishes test-only use from code
with no recognized use at all.
See [rule evidence](how-it-works.md#evidence-used-by-each-rule).

### Report only new findings using a baseline {#baseline}

Save existing findings, then omit matching findings on later runs so CI can
report newly introduced issues while cleanup proceeds gradually. Kareki uses
`--baseline` and `--write-baseline` to load and save that record.
See the [baseline guide](baseline.md).

### Stale exclusions and baseline entries {#stale-configuration}

Find exclusions, suppression comments, and baseline entries that no longer
apply, for example because the target file or unused declaration was removed.
`kareki doctor` reports these issues without changing files; uncertain analysis
can prevent usage-dependent checks from completing.
See [doctor's checks](doctor.md#checks).

## Analysis differences

Kareki follows references from entry points, so it can detect public declarations
that only reference each other. Generated code, configuration, and dynamic-call
handling can still retain them. Ciach's `--transitive` detects declarations
referenced only by dead code, but not cycles. Dart Code Linter checks whether
references exist. See [ciach's documentation][ciach-transitive] and
[Dart Code Linter's implementation][dcl-analyzer].

Ciach also distinguishes same-name declarations and collects cross-package
references; neither is unique to kareki. See [ciach's implementation][ciach-finder]
and [monorepo documentation][ciach-readme].

## Using the tools together

Kareki leaves unused private declarations and members to standard Dart analysis,
adding public API and cross-package checks. Keep `dart analyze` / `flutter analyze`
for those private-code checks, type checking, and linting.
See [Dart's unused-declaration diagnostic][dart-unused].

dependency_validator also covers missing dependencies and incorrect
placement in `dependencies` / `dev_dependencies`, beyond unused dependencies.
See [dependency_validator's documentation][dependency-readme].

Speed and false-positive rates have not been benchmarked across these tools.
A ✅ does not guarantee safe deletion. Review findings and test changes,
especially for published APIs and dynamic calls.

## Versions compared

Checked October 10, 2026, against official documentation and source.

| Tool | Version examined |
|---|---|
| kareki | [latest][kareki-source] |
| [ciach][ciach-repo] | [0.6.0][ciach-readme] |
| [Dart Code Linter][dcl-repo] | [4.4.2][dcl-readme] |
| [dependency_validator][dependency-repo] | [5.1.0][dependency-readme] |
| [Dart standard analysis][dart-unused] | [3.13.3][dart-unused] |

[kareki-source]: https://github.com/ostk0069/kareki/tree/main
[ciach-readme]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md
[ciach-transitive]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md#transitively-dead-code
[ciach-finder]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/lib/src/finder.dart
[dart-unused]: https://dart.dev/tools/diagnostics/unused_element
[dart-parameter]: https://dart.dev/tools/diagnostics/unused_element_parameter
[dcl-readme]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md
[dcl-cli]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md#cli
[dcl-analyzer]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/unused_code_analyzer/unused_code_analyzer.dart
[dcl-parameters]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/lint_analyzer/rules/rules_list/avoid_unused_parameters/visitor.dart
[dcl-l10n]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/cli/commands/check_unused_l10n_command.dart
[dependency-readme]: https://github.com/Workiva/dependency_validator/blob/7728cb7f27de46d3fefc515018f54b9aee3a2587/README.md

[ciach-repo]: https://github.com/leancodepl/ciach
[dcl-repo]: https://github.com/bancolombia/dart-code-linter
[dependency-repo]: https://github.com/Workiva/dependency_validator
