# How it works

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
| analyzer | `^9.0.0` |

Newer analyzer versions will be added incrementally; the choice of 9.x lets projects that have not yet migrated to analyzer 10+ adopt kareki today.
