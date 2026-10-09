---
title: Analysis internals
weight: 9
---

This reference describes implementation constraints for contributors and warning
reviews. Start with [how it works](how-it-works.md) for the user-facing overview.

## Library API

Runner APIs are asynchronous. Use an `async` caller and await the result:

```dart
final result = await KarekiRunner().run(request);
// analyze(request) is also asynchronous.
```

`DoctorRunner.run`, `DoctorRunner.analyze`, `runCli`, and `runDoctor` also return
Futures. The [runnable example](https://github.com/ostk0069/kareki/blob/main/example/example.dart)
shows request construction and result reporting.

The preview names `runCliAsync` / `runDoctorAsync`, `AnalysisMode` and its
arguments, and legacy name-reference metadata on `ParsedFile`,
`DeclarationRecord`, and `EntryPointSet` have been removed.
These API changes do not change the `dart run kareki` command.

## Declaration identity and graph construction

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

## Conditional imports and exports

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

## Decoder values

Closed, read-only flows from supported JSON and YAML decoders can be checked
without retaining unrelated workspace `[]` operators. The decoder identity and
every use of the decoded value must satisfy the model. Unsupported flows keep
the conservative fallback. See [decoder models](decoder-models.md) for the full
conditions, source verification, and review procedure.

## Optional arguments

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

### Direct-use callbacks

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

### Stored callbacks

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

## Warning evidence

Warnings include evidence for review, not an automatic true/false-positive
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

For output streams and exit codes, see the [CLI reference](cli.md) and
[doctor](doctor.md).

## Reuse within an analysis

Doctor shares one resolved source snapshot across its usage-dependent checks.
Graph assembly uses indexed declarations and references. Resolved library units
are reused across parts in the same analysis context, and test-source
classification and inherited-method lookups are cached within the run.

There is no persistent analysis cache. These optimizations do not narrow the
source scope or relax the safety conditions above.

To compare performance, run `dart tool/resolved_analysis/benchmark.dart ROOT [doctor]`
with the same SDK, sources, configuration, and rules. Measure multiple fresh
processes and peak memory (RSS); keep source changes separate from engine changes.
