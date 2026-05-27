# kareki example

This directory is a real, runnable Dart package. Every file under `lib/`
is wired so that running kareki produces exactly **one finding per
rule** — six in total. Use it to see what each rule actually catches.

## Layout

```
example/
├── pubspec.yaml         # declares `collection` but never imports it → unused_pub_dependency
├── kareki-config.yaml   # minimum config kareki picks up by default
├── bin/main.dart        # entry point — keeps everything else reachable
├── lib/
│   ├── api.dart         # public class no one uses → unused_element
│   ├── parameters.dart  # body-unused arg → unused_parameter
│   │                    # never-passed optional → unused_parameter_optional
│   ├── test_only.dart   # only test/ references it → test_only_used
│   └── orphan.dart      # never imported → unused_file
├── test/api_test.dart   # references test_only.dart (test-side only)
└── example.dart         # programmatic API demo (run from this dir)
```

## Run kareki on this example

From the repo root:

```sh
$ dart run kareki --root example
• Package: kareki_example
  [test_only_used] lib/test_only.dart:3:8
    Public function 'testOnlyHelper' is only referenced from test code.
  [unused_element] lib/api.dart:14:7
    Unused public classDecl 'UnusedPublicApi'.
  [unused_file] lib/orphan.dart:1:1
    File is never imported, parted, or exported.
  [unused_parameter] lib/parameters.dart:10:26
    Parameter 'unusedTwo' of 'Service.doWork' is never used.
  [unused_parameter_optional] lib/parameters.dart:3:49
    Optional parameter 'port' of 'buildUrl' is never passed at any call site.
  [unused_pub_dependency] pubspec.yaml:1:1
    Dependency 'collection' is declared in pubspec.yaml but never imported within 'kareki_example'.

kareki: 6 finding(s) across 1 package(s).
```

## Rule-by-rule walkthrough

| Rule | Where it's planted | Why it fires |
|---|---|---|
| `unused_element` | `lib/api.dart` — `UnusedPublicApi` | Public class declared in a file that *is* imported by `bin/main.dart` (via `greet`), but nobody references the class itself. |
| `unused_file` | `lib/orphan.dart` | The file is never imported, parted, or exported from anywhere in the package. (The single declaration inside is `_OrphanWidget` — private — so `unused_element` does not double-fire.) |
| `unused_pub_dependency` | `pubspec.yaml` — `collection` | Declared under `dependencies:` but no source file imports `package:collection/...`. `meta`, which `lib/api.dart` does import, is not flagged. |
| `test_only_used` | `lib/test_only.dart` — `testOnlyHelper` | Defined in `lib/` (production source) but the only reference comes from `test/api_test.dart`. Production reachability is empty. |
| `unused_parameter` | `lib/parameters.dart` — `Service.doWork(int a, int unusedTwo)` | `unusedTwo` is never referenced in the method body. |
| `unused_parameter_optional` | `lib/parameters.dart` — `buildUrl({String host, int port})` | `port` has a default value but no call site in the workspace ever passes it. |

## Filter to one rule at a time

```sh
$ dart run kareki --root example --rule unused_pub_dependency
$ dart run kareki --root example --rule unused_parameter --rule unused_parameter_optional
```

## JSON output for CI

```sh
$ dart run kareki --root example --format json | jq '.findings | length'
6
```

## Programmatic API

[`example.dart`](example.dart) runs the same analysis through the public
Dart API. From inside this directory:

```sh
$ dart pub get
$ dart run example.dart
```

```dart
import 'package:kareki/kareki.dart';

void main() {
  const root = '.';
  final config = KarekiConfig.load(root);
  final result = KarekiRunner().run(
    RunRequest(rootPath: root, config: config),
  );
  print(TextReporter().render(result.findings, rootPath: root));
}
```

## Configuration

See [`kareki-config.yaml`](kareki-config.yaml) for the minimum config
this example uses, and [`doc/configuration.md`](../doc/configuration.md)
for the full schema (presets, custom annotations, ignore lists,
baseline, etc.).
