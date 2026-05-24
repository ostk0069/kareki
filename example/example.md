# kareki examples

Most users invoke kareki through its CLI; the entries below cover both
the CLI and the programmatic API.

## CLI — default text output

```sh
$ cd path/to/your-monorepo
$ dart run kareki

• Package: analytics
  [unused_element] lib/event/value/seek_reason.dart:1:6
    Unused public enumDecl 'SeekReasonA'.
• Package: app
  [unused_file] lib/foundation/slo/slo_sampling_rate.dart:1:1
    File is never imported, parted, or exported.
• Package: legacy_data
  [unused_pub_dependency] pubspec.yaml:1:1
    Dependency 'rxdart' is declared in pubspec.yaml but never imported within 'legacy_data'.

kareki: 3 finding(s) across 3 package(s).
```

## CLI — JSON for CI

```sh
$ dart run kareki --format json | jq '.findings | length'
3
```

## CLI — restrict to a single rule

```sh
$ dart run kareki --rule unused_pub_dependency
```

## CLI — restrict to specific packages

```sh
$ dart run kareki --packages app --packages domain
```

## Programmatic API

See [`example.dart`](example.dart):

```dart
import 'package:kareki/kareki.dart';

void main() {
  const root = '.';
  final config = KarekiConfig.load(root);
  final result = KarekiRunner().run(
    RunRequest(rootPath: root, config: config),
  );
  // ignore: avoid_print
  print(TextReporter().render(result.findings, rootPath: root));
}
```

## kareki-config.yaml

See [`docs/configuration.md`](../docs/configuration.md) for the full schema, and [`example/kareki-config.yaml`](kareki-config.yaml) for a runnable minimum.

```yaml
keep_alive_annotations:
  presets: [freezed, riverpod, json_serializable, auto_route]

custom_presets:
  my_internal_di:
    keep_alive_annotations: [Injectable]
    annotation_implied_packages:
      Injectable: [my_di_package]

ignore:
  packages: [internal_library_pkg]
  dependencies:
    my_app:
      - geolocator_android
      - google_sign_in_ios
```
