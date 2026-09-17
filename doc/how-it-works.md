# How it works

**English** | [日本語](how-it-works.ja.md)

1. Discover packages via `melos.yaml` or pub workspace.
2. Parse every `.dart` file with `package:analyzer`, extracting declarations + outgoing simple-name references.
3. Resolve entry points (implicit conventions + active presets + generated-file references + config).
4. BFS the simple-name graph from those root identifiers.
5. Report unreached declarations, unreferenced files, and undeclared pub deps.

## Entry-point seeding

Entry-point seeding combines four layers:

| Layer | Source |
|---|---|
| Implicit | Dart / Flutter SDK conventions (`main`, `_test`, `bin/`, `integration_test/`, `lib/l10n/`, `flutter_test_config.dart`). |
| Tool conventions | `entry_points.files` config (defaults: playbook / widgetbook globs). |
| Annotations | Active preset keep-alives + `custom_presets.*.keep_alive_annotations` + `keep_alive_annotations.custom`. |
| Generated code | Files matching `exclude.files` or carrying a `GENERATED CODE` header — their identifier references seed BFS roots. |

This layered design lets kareki coexist with codegen-heavy ecosystems without flooding you with false positives.

## Supported versions

| Component | Version |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `>=10.2.0 <15.0.0` |

CI runs analysis and tests against every supported Dart minor version, plus the
latest stable SDK patch. Separate boundary jobs test analyzer 10.2.0 and the
latest analyzer version allowed by the package constraint.

The parser recognizes Dart language features through Dart 3.13, including
primary constructors and concise `new` / `factory` declarations. Declaring
parameters participate in `unused_element` as fields, while ordinary primary
constructor parameters participate in the parameter rules.
