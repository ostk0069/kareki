---
title: How it works
weight: 6
aliases:
  - /analysis-internals/
---

Kareki follows references across a Dart / Flutter workspace to find code that
has no recognized use. This guide is for developers who want to understand why
a declaration is reported, apparently unused code is retained, or an analysis
warning appears. It explains the analysis with code examples, then shows how
to review the results.

## Analysis flow

Consider these two files in a package named `example_app`, using default settings.
File-path comments separate files in all examples below.

```dart
// lib/stores.dart
class LocalStore {
  void save() {}
}

class RemoteStore {
  void save() {}
}

// bin/main.dart
import 'package:example_app/stores.dart';

void main() => LocalStore().save();
```

1. **Discover packages and files.** Read workspace/configuration settings and
   collect package-root scripts and the supported source directories, including
   `lib/`, `bin/`, tests, and tooling. `--packages` limits reports, not reference
   collection: another package may call the selected package's code.
2. **Collect declarations.** Parse classes, methods, parameters, imports, and
   suppression comments. Identify generated/excluded files, but keep them as
   reference sources. Here, the two `save` methods are separate declarations.
3. **Resolve references.** Dart analyzer binds `LocalStore().save()` to
   `LocalStore.save`, not `RemoteStore.save`. Internally, library, source file,
   declaration position, and kind distinguish the targets. Missing dependencies
   or source errors stop this analysis rather than switching to name matching.
4. **Build and follow reference links.** Record links from callers to declarations,
   including constructor, enclosing-type, and inheritance relationships. Start
   from entry points such as `main`, entry files, and configured annotations.
   Here the path reaches `LocalStore` and its `save`; no path reaches `RemoteStore`.
   Entry-point files can retain all their declarations, so moving a class into
   `bin/main.dart` can change the result.
5. **Evaluate the rules.** With no other references, `RemoteStore` and
   `RemoteStore.save` receive `unused_element` findings. Other rules answer
   different questions, as shown below.
6. **Apply reporting controls.** Apply rule/name exclusions, suppression comments,
   and package filters; the CLI then applies the baseline. Analysis warnings are
   separate from findings, not extra unused-code rules.

## Analysis scope and rules

### Source scope and reporting scope

`--packages` and `ignore.packages` only limit reporting: consumers in other
discovered packages still contribute references. In contrast, `packages.exclude`
removes packages from discovery. See [configuration](configuration.md) for source
directories and scope settings.

### Entry points

Entry points are code treated as used without a caller. Four sources provide them:

| Source | Examples |
|---|---|
| Dart / Flutter conventions | Top-level `main`, test files, `bin/`, `integration_test/`, `lib/l10n/`, and `flutter_test_config.dart`. |
| Configuration | `entry_points.files` and `entry_points.names`; default file patterns cover stories and widgetbook. |
| Annotations | Built-in and custom presets, plus `keep_alive_annotations.custom`. |
| Generated or excluded files | Their declarations and outgoing references remain part of the graph, although the files are not reported as unused. |

Generated code can therefore keep its source declarations in use. Run code
generation before analysis; kareki does not generate missing files.

Explicit `entry_points.names` settings match by name, unlike resolved calls.

### Evidence used by each rule

This walkthrough includes rules that need resolved references. Syntax-only rules
can skip graph construction; each rule uses different evidence:

| Rule | Evidence it uses |
|---|---|
| `unused_element` | Whether an eligible public declaration is reachable from any entry point. |
| `test_only_used` | Whether it is reachable from test entry points but not production entry points. |
| `unused_parameter` | Whether a parameter is referenced inside its function body. |
| `unused_parameter_optional` | Whether callers supply an optional parameter; all scanned calls count, including generated and unreachable code. Unknown call paths prevent an unused verdict. |
| `unused_file` | Whether another scanned file imports, exports, or parts the file, or it is an entry point. This is not declaration reachability. |
| `unused_pub_dependency` | Imports and recognized annotation, build-configuration, native-plugin, and asset usage. |

### Optional-argument usage

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

## Cases that are harder to decide

In the following examples, “retain” means not reporting something as unused.
It does not mean that kareki has proved it executes at runtime. Examples assume
no additional callers or suppression settings.

### 1. A dynamic receiver hides the method target

```dart
// lib/stores.dart
class LocalStore {
  void save() {}
}

class RemoteStore {
  void save() {}
}

void persist(dynamic store) => store.save();

// bin/main.dart
import 'package:example_app/stores.dart';

void main() => persist(LocalStore());
```

**Why it is difficult:** inside `persist`, the receiver's static type is
`dynamic`. A reader can see the value passed by this caller, but kareki does not
propagate every concrete object through function calls to recover its type.

**What kareki does:** it retains both same-name `save` candidates when this call
is reachable and emits an `Unresolved reference "save"` warning. The candidates
are possibilities, not confirmed runtime targets. This fallback is different
from the exact binding in the first example.

**What to check:** trace the values passed to `persist`. If its actual contract
only accepts `LocalStore`, expressing that type lets the reference resolve.
Do not narrow a genuinely multi-type API just to silence a warning.

### 2. A saved callback hides how optional arguments will be supplied

```dart
// lib/callbacks.dart
void save({bool force = false}) => print(force);

void Function()? pending;
void register(void Function() callback) {
  pending = callback;
}

// bin/main.dart
import 'package:example_app/callbacks.dart';

void main() {
  register(save);
  pending?.call();
}
```

**Why it is difficult:** `save` is passed as a value and stored before being
called. To prove that `force` is never supplied, the analyzer would need to follow
all reads and transfers of that value. A `void Function()` view does not erase
the original function's optional parameter.

**What kareki does:** this example retains `force` and emits an argument-usage
warning. The body reads `force`, so this is about `unused_parameter_optional`,
not the separate `unused_parameter` rule. A direct synchronous consumer is a
narrower case that kareki can check:

```dart
// lib/callbacks.dart
void save({bool force = false}) => print(force);

void runNow(void Function() callback) => callback();

// bin/main.dart
import 'package:example_app/callbacks.dart';

void main() => runNow(save);
```

Here every use of the consumer's parameter is a direct call without `force`.
With no other uses, `force` receives `unused_parameter_optional`. Saving,
forwarding, or capturing the callback breaks this particular proof. Some
external stored-callback models can establish potential argument usage, but
cannot prove that unobserved arguments are unused.

**What to check:** follow storage, forwarding, and eventual calls, not just the
registration site. A known call such as `save(force: true)` establishes usage
even if another path remains unknown. Manual inspection alone does not change
kareki's result.

### 3. Conditional exports select different code on different platforms

```dart
// lib/backend.dart
export 'backend_stub.dart'
    if (dart.library.io) 'backend_io.dart';

// lib/backend_stub.dart
class Backend {
  String get name => 'stub';
}

// lib/backend_io.dart
class Backend {
  String get name => 'io';
}

// bin/main.dart
import 'package:example_app/backend.dart';

void main() => print(Backend().name);
```

**Why it is difficult:** resolving the selected `Backend` on the current host
does not establish whether the alternative is needed on another platform.
Analyzing source is not the same as building every supported target.

**What kareki does:** this class-based example retains the alternatives and
emits a conditional import/export warning. For a narrower facade consisting of
parameterless functions/getters with matching explicit return-type identities,
kareki can link the alternatives instead of retaining every declaration.
That does not prove platform-specific runtime correctness.

**What to check:** review every supported branch and run its relevant builds or
tests before removing platform code. Build scripts that replace files require
separately prepared source variants; kareki does not run those scripts.

### 4. JSON returns dynamic values, but not every dynamic index is arbitrary

```dart
// lib/lookup.dart
class Lookup {
  Object? operator [](String key) => readKey(key);
}

Object? readKey(String key) => key;

// bin/main.dart
import 'dart:convert';

void main() {
  final data = jsonDecode('{"name":"Ada"}');
  print(data['name'] as String);
}
```

**Why it is difficult:** `jsonDecode` returns `dynamic`. Looking only at the
type of `data['name']` would leave custom `[]` operators, such as `Lookup.[]`,
as possible targets. Looking at the name `jsonDecode` alone is also insufficient:
a different function could return arbitrary objects.

**What kareki does:** it recognizes the SDK decoder and checks the value's uses.
This closed, read-only scalar access cannot invoke `Lookup.[]`, so it does not
keep `readKey` alive or produce an unresolved-`[]` warning. Operators themselves
are not reported by `unused_element`; the declarations they call can be.

Mutation or passing the decoded container elsewhere invalidates this limited
proof. For example, replace `bin/main.dart` with:

```dart
// bin/main.dart
import 'dart:convert';
import 'package:example_app/lookup.dart';

void main() {
  final data = jsonDecode('{}');
  data['nested'] = Lookup();
  print(data['nested']['name']);
}
```

Now an application object really can appear in the container. Kareki retains
the candidate operator's references, including `readKey`, and emits a warning.

**What to check:** follow the container's origin and all its uses, including
later mutations and transfers. Similar JSONC/YAML support requires reviewed
dependency sources; upgrading a dependency may disable the model and restore
warnings. The model does not validate JSON shape or guarantee a cast succeeds.

### 5. Generated code can be the only caller

```dart
// lib/customer.dart
class Customer {
  String name = '';
}

// lib/customer.g.dart
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'customer.dart';

String generatedName(Customer customer) => customer.name;

// bin/main.dart
void main() {}
```

**Why it is difficult:** excluding generated files from analysis altogether
would hide their references to handwritten declarations. Looking only at
handwritten calls would miss the use of `Customer.name`.

**What kareki does:** generated files are excluded from findings but their
declarations and references act as entry points. This example therefore retains
`Customer` and `name`, even though `main` does not call `generatedName`.
Files in `exclude.files` receive the same protection. This deliberately favors
retaining potentially needed code over reporting more unused code.

**What to check:** regenerate outputs before analysis. Stale generated code can
keep stale references alive; missing outputs that break resolution stop the
analysis. Do not edit generated files just to change the report. Some generators
also read declarations without emitting a normal call; supported presets cover
specific cases, not arbitrary generator behavior.

## Reviewing the results

Findings mean unused **within the analyzed scope**. External callers and builds
not represented in that scope still need review. Warnings identify gaps in the
analysis, not declarations to delete or confirmed false positives.

Use the warning's source locations, candidate targets, and unproven parameters
to investigate the corresponding case above. If uncertainty remains, keep the
affected code. [Doctor](doctor.md) skips usage-dependent cleanup while analysis
warnings remain; an empty report in that state is not a clean bill of health.
Output streams and exit codes are described in the [CLI reference](cli.md).

Before deleting code, review the finding and any warnings. After deletion,
regenerate sources and run the project's analysis, tests, and relevant builds.

## Supported versions

| Component | Version |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `>=10.2.0 <15.0.0` |

CI runs analysis and tests against every supported Dart minor version and the
latest stable SDK patch.
