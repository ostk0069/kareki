---
title: How it works
weight: 6
---

Kareki uses a single declaration-identity analysis engine:

1. Discover packages via `melos.yaml` or pub workspace.
2. Parse every `.dart` file with `package:analyzer`, extracting declaration metadata and suppression directives.
3. Resolve entry points (implicit conventions + active presets + generated-file references + config).
4. Resolve references with analyzer and traverse the graph of exact declaration identities.
5. Report unreached declarations, unreferenced files, and undeclared pub deps.

## Entry-point seeding

Entry-point seeding combines four layers:

| Layer | Source |
|---|---|
| Implicit | Dart / Flutter SDK conventions (`main`, `_test`, `bin/`, `integration_test/`, `lib/l10n/`, `flutter_test_config.dart`). |
| Tool conventions | `entry_points.files` config (defaults: playbook / widgetbook globs). |
| Annotations | Active preset keep-alives + `custom_presets.*.keep_alive_annotations` + `keep_alive_annotations.custom`. |
| Generated code | Files matching `exclude.files` or carrying a `GENERATED CODE` header — their resolved declarations and references seed the graph. |

This layered design lets kareki coexist with codegen-heavy ecosystems without flooding you with false positives.

## Resolved analysis

The analysis engine uses `AnalysisContextCollection` to resolve
references and builds a graph keyed by defining library, physical source file,
declaration offset and kind. This internal identity is separate from baseline
IDs. Roots from entry files, generated files and annotations use individual
declarations; explicit `entry_points.names` deliberately still matches names.
Each physical source is collected once, owned by the innermost discovered
workspace package. Statically known Record field accesses do not retain
unrelated same-name declarations.
Built-in `.call()` on function types is also distinguished from ordinary
members, and null assertions retain the original read target instead of being
treated as updates. Import/export show and hide names retain reference edges
without counting as escaped function values. Actual callbacks and dynamic
calls remain conservatively protected.

Generic member substitutions and induced field accessors map back to their
original definitions. Members retain their enclosing types, constructors retain
their implicit super/redirect targets, and reachable types conservatively retain
inherited implementations and runtime hooks (`call` / `toJson`). Unresolved
references retain matching candidates when their source is reachable and produce
warnings. Conditional directive targets are conservatively retained across
platforms. This remains a static approximation, not whole-program dynamic
dispatch or reflection analysis.

A narrow conditional-facade proof replaces blanket roots with references to
every alternative when all target files are resolved, non-test libraries with
the same public parameterless functions/getters and explicit return types.
Types are compared by declaration identity and nullability, not display name.
All alternatives are joined, including custom conditions; no platform value is
assumed. Types/variables, exports/parts, nested conditional imports, parameters
(including private helpers), inferred/generic/workspace public return types, missing
targets or incompatible namespaces keep the existing protection. Resolution
errors still abort analysis. This proves only local binding substitution, not
runtime or SDK compatibility across platforms.

One limited value-origin proof covers `dart:convert`'s `jsonDecode(source)` and
the standard `json.decode(source)` without a reviver. It follows read-only nested
indexes, supported core casts and final local aliases, checking every reference
in the unit. The flow must end in an immutable scalar cast or a core Map's keys
view, or remain an unused final local. Storage, return, argument passing, capture,
mutation and unsupported operations invalidate the proof for the entire origin,
even if they occur after a read. Such closed reads cannot call a workspace `[]`
operator; receiver and index argument references are still visited normally.
This does not prove the JSON shape or runtime success. Custom/aliased codecs,
explicit revivers (including null) and mutable locals remain outside
this proof. Declaration identity and the exact SDK receiver, not a `decode` name
or a `JsonCodec` type alone, establish the decoder contract.

External decoder support uses **reviewed source models**, not arbitrary body
inference. `jsoncDecode` / the default `jsonc.decode` and `loadYaml` are modeled
only when the defining library and its entire resolved non-SDK import/export/
part closure match an audited SHA-256 fingerprint, including effective language
versions. The catalog covers jsonc 0.0.3 and yaml 3.1.3 / 3.1.4 with reviewed
dependencies; names and version numbers alone never enable a model. A changed,
missing, ambiguous or unreviewed source falls back to conservative retention.
Approvals are cached only within an analysis, and scanned workspace-owned
decoder sources are excluded from this external-only optimization.

The same closed-use proof supports synchronous `for (final item in list)`
statements over a core List from a modeled decoder, including aliases and nested
reads. Mutable loop bindings, custom Iterables, collection-for, await-for,
capture, mutation and escape remain unsupported. A successful YAML model also
allows its YamlMap/YamlList casts and YamlMap keys: unlike JSON keys, YAML keys
may be containers, but the reviewed loader creates read-only decoded containers.
Null comparisons are read-only. Decoder hooks and explicit named options remain
unsupported. These models neither guarantee valid input nor suppress all
dynamic calls in a file. To review an upgrade, use
`tool/resolved_analysis/decoder_model_snapshot.dart SOURCE_FILE LIBRARY_URI` to
inspect the source closure, audit the implementation, add regression tests and
only then update the catalog; the tool never trusts a new digest automatically.

Use `await KarekiRunner().analyze(request)` or `await KarekiRunner().run(request)`.
Both APIs are asynchronous. See [migration notes](migration.md).

Optional argument usage is keyed by the same declaration identity and aggregates
all scanned call sites, including unreachable/generated code. Usage propagates
through actual override families and redirecting factories, not through unrelated
names. Tear-offs, implicit callable conversions, dynamic calls and
unselected conditional targets are protected conservatively where exact usage
cannot be established. Callback analysis is limited to the direct-use consumers
described below; this is not general interprocedural data-flow analysis.
Super formals mark their exact parent parameters as supplied, including default
values forwarded when omitted by the child caller. If known calls already prove
usage of every optional parameter, an additional escaped callback does not make
the unused-argument decision uncertain. Callbacks with even one unproven optional
parameter remain protected where a call path is still unknown.

Each optional parameter has a `used`, `unused`, or `unknown` state. Known usage
wins even if other paths are unknown. `unused` means no scanned call supplies
the argument and no unknown call path remains **within the analysis scope**;
it does not certify external API non-use or authorize deletion. Findings require
this per-parameter `unused` state. Existing suppressions and generated-file
reporting policies still apply.

For a function value supplied as a complete argument to a statically resolved
top-level function, static method or extension method, the adapter
inspects the consumer's synchronous body. Every reference to that exact formal
parameter must directly invoke it (`callback(...)` or built-in `callback.call(...)`),
or the parameter must not be referenced. Returning the invocation result is
allowed, including yielding the result from a synchronous generator (`sync*`).
Storing, yielding, returning, forwarding, aliasing, casting, reassigning or capturing
the function value itself invalidates the proof. Selected non-SDK dependency
consumers are resolved in their original analysis session, including parts; missing
or erroneous bodies retain protection. Dependency bodies do not become finding
or entry-point sources. Async bodies, virtual methods (including `BuiltList.map`),
function-variable consumers, and SDK bodies are not summarized.
Summaries aggregate positional/named arguments and are applied after all files
have been visited, before override/redirect propagation. Neither library names
nor a callback's narrow function type are accepted as proof of safety.

Stored callbacks have a separate, positive-only analysis. For selected external
constructors it follows unchanged constructor arguments, redirecting factories,
and final function fields to actual field-invocation expressions. It collects
supplied argument positions/names but **never establishes non-use or closes an
escaped callback**. Fields are keyed by declaration identity; instances of the
same field are not distinguished. These are conservative potential-use paths,
not proof that a particular object or runtime branch executes the call.
Unmodeled uses/reassignment of a constructor parameter invalidate its transfers.
Mutable fields, explicit getters, arbitrary aliases/casts, and cross-package
forwarding are not modeled. The import/export closure is limited to 128 libraries
in the selected dependency package and original analysis session. Workspace
sources, resolution errors or exceeded limits discard that group's evidence.
Warnings distinguish potential field-flow invocation evidence from unknown paths;
an argument without observed usage still stays `unknown` after callback storage.

Warnings now include evidence for review, not an automatic true/false-positive
verdict. Argument warnings list the unproven parameters, known argument counts
and names, and function-value/other uncertainty locations. For a direct callback
argument to a virtual method, they also include the static consumer declaration,
receiver type, and field/getter/local references from leaf to root where available.
These are static bindings, **not proven runtime origins**: final fields, public
factories, `copyWith`, and casts do not by themselves close a value's provenance.
No protection is removed using this diagnostic context. Override and redirect
propagation preserve the originating reasons. Unresolved references list every
site, available receiver static types, and candidate declarations; candidates
are not proven runtime targets. Conditional warnings list directives, conditions,
and workspace targets. Argument/data literals are not copied into these
diagnostics; conditional directive URIs and comparison values are shown.
Trace the listed values through their consumers (including pinned dependencies)
before concluding non-use. Manually reviewed evidence does not disable warnings,
change findings, or unblock doctor cleanup.

## Supported versions

| Component | Version |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `>=10.2.0 <15.0.0` |

CI runs analysis and tests against every supported Dart minor version, plus the latest stable SDK patch.
