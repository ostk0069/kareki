---
title: Analysis internals
weight: 9
sidebar:
  exclude: true
---

This maintainer reference explains the safety principles behind the analysis.
For everyday use, see [how it works](how-it-works.md).

## Analysis principles

References are resolved to individual declarations, so unrelated declarations
with the same name do not share usage. Generated and excluded sources still
contribute references; report filters do not hide consumers.

A finding means unused **within the analyzed scope**, not safe to delete in
every build or downstream application. Missing evidence of use is not, by itself,
evidence of non-use.

## When not to report unused code

- If a call path cannot be checked, retain the potentially used declaration or
  parameter. A known call can establish argument usage even when other paths
  remain unknown.
- Tracking a stored callback can establish potential usage, but cannot prove
  non-use or account for every call. Do not remove that protection just because
  no argument usage was observed.
- Narrow models for callbacks, conditional imports, and decoded values apply
  only when all their checks pass. Unsupported flows keep conservative
  protection; resolution failures do not fall back to the old analysis engine.

Exact supported constructs and limits belong in the
[implementation](https://github.com/ostk0069/kareki/blob/main/lib/src/reachability/resolved_reachability.dart)
and [regression tests](https://github.com/ostk0069/kareki/tree/main/test/runner).
When extending a model, test both the newly supported case and cases that must
remain protected. External decoder model reviews are described in
[decoder models](decoder-models.md).

## Limits of warning evidence

Warnings identify uncertain parameters, relevant source locations, static
receiver types, or candidate declarations. These are review aids, not proof of
runtime targets or a verdict that a finding is a false positive.

Trace the reported values through their consumers, including dependencies.
Manual review does not change the analyzer's decision or clear its warnings.
[Doctor](doctor.md) skips usage-dependent cleanup checks while warnings remain;
an empty result in that state is not a clean bill of health.
