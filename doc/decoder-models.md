---
title: Decoder models
weight: 10
---

This developer reference describes when decoded values can be treated as
read-only data without retaining unrelated workspace `[]` operators.
These checks do not guarantee the input's shape or runtime success.

## SDK JSON decoding

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

## Source-verified external decoders

External models apply only to dependencies, never to scanned workspace sources.
They are reviewed contracts, not assumptions based on package or method names.

| Model | Reviewed versions | Entry points |
|---|---|---|
| JSONC | jsonc 0.0.3 | `jsoncDecode`, standard `jsonc.decode` (`JsoncCodec.decode`). |
| YAML | yaml 3.1.3 and 3.1.4 with reviewed dependencies | `loadYaml`. |

The catalog in `external_decoder_models.dart` verifies a SHA-256 fingerprint of
the complete resolved non-SDK import/export/part closure. Each source contributes
its library URI, source URI, effective language version, and content digest.
Absolute installation paths are not trusted identities.

A changed, missing, ambiguous, unreadable, or unreviewed source disables the
model. Version numbers alone never enable it. Verification is cached only within
the current analysis. Unrecognized versions still use conservative analysis;
they may produce warnings until reviewed.

## Read-only iteration and YAML containers

The same closed-use check supports synchronous `for (final item in list)`
statements over a core List from a modeled decoder, including final aliases and
nested reads. Mutable loop bindings, custom Iterables, collection-for,
await-for, capture, mutation, and escape remain unsupported.

The YAML model also permits YamlMap/YamlList casts and YamlMap keys. YAML keys may
be containers, but the reviewed loader creates read-only decoded containers.
Null comparisons are read-only. Decoder hooks, explicit named options, and
arbitrary subclasses remain unsupported. A model does not exempt other dynamic
calls in the file.

## Reviewing a model update

Before adding a fingerprint:

1. Review the defining decoder and its transitive implementation sources.
2. Verify that decoded values cannot dispatch to arbitrary workspace operators.
3. Run `tool/resolved_analysis/decoder_model_snapshot.dart SOURCE_FILE LIBRARY_URI`
   to inspect the source closure. Generating a digest alone is not approval.
4. Extend positive and counterexample tests in
   `test/runner/resolved_decoders_test.dart`: source changes, relocation,
   same-name impostors, mutation, escape, and vendored implementations.
5. Update the catalog only after the review and tests pass.

For the surrounding analysis, see [analysis internals](analysis-internals.md).
