---
title: Comparing similar tools
weight: 8
---

Kareki focuses on workspace-wide unused code detection and ongoing cleanup in CI.

## Feature comparison

✅ Supported (including opt-in features), △ partially supported, — no equivalent feature.

| Feature | **kareki** | [ciach][ciach-options] | [Dart Code Linter][dcl-cli] | [dependency_validator][dependency-readme] | [Dart standard analysis][dart-unused] |
|---|:---:|:---:|:---:|:---:|:---:|
| [Detect unused public declarations and members](how-it-works.md#analysis-flow) | ✅ | ✅ | ✅ | — | — |
| Detect unused private declarations and members | — | ✅ | ✅ | — | ✅ |
| Detect unused values of public enums | — | ✅ | ✅ | — | — |
| [Detect cycles of public declarations unreachable from entry points](#analysis-differences) | ✅ | — | — | — | — |
| [Detect unused Dart files](how-it-works.md#evidence-used-by-each-rule) | ✅ | — | ✅ | — | — |
| [Detect unused pub dependencies](configuration.md#dependency-usage-beyond-imports) | ✅ | — | — | ✅ | — |
| [Detect optional public API parameters never supplied by callers](how-it-works.md#optional-argument-usage) | ✅ | — | — | — | — |
| [Detect public declarations used only by tests](how-it-works.md#evidence-used-by-each-rule) | ✅ | — | — | — | — |
| Dedicated unused-l10n checks | Coming soon | — | ✅ | — | — |
| [Report only new findings using a baseline](baseline.md) | ✅ | — | — | — | — |
| [Check stale exclusions and baseline entries](doctor.md#checks) | ✅ | — | — | — | — |
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
| ciach | [0.6.0][ciach-readme] |
| Dart Code Linter | [4.4.2][dcl-readme] |
| dependency_validator | [5.1.0][dependency-readme] |
| Dart standard analysis | [3.13.3][dart-unused] |

[kareki-source]: https://github.com/ostk0069/kareki/tree/main
[ciach-readme]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md
[ciach-transitive]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md#transitively-dead-code
[ciach-finder]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/lib/src/finder.dart
[ciach-options]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/lib/src/cli/args.dart
[dart-unused]: https://dart.dev/tools/diagnostics/unused_element
[dart-parameter]: https://dart.dev/tools/diagnostics/unused_element_parameter
[dcl-readme]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md
[dcl-cli]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md#cli
[dcl-analyzer]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/unused_code_analyzer/unused_code_analyzer.dart
[dcl-parameters]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/lint_analyzer/rules/rules_list/avoid_unused_parameters/visitor.dart
[dcl-l10n]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/cli/commands/check_unused_l10n_command.dart
[dependency-readme]: https://github.com/Workiva/dependency_validator/blob/7728cb7f27de46d3fefc515018f54b9aee3a2587/README.md
