# External decoder models

These are reviewed contracts, not proofs inferred from a package or method name.
They apply only to external dependencies, never to vendored workspace sources.

The JSONC model covers `jsoncDecode` and `JsoncCodec.decode` in jsonc 0.0.3:
their standard decoder produces JSON values. The YAML model covers `loadYaml`
in yaml 3.1.3 and 3.1.4 with the reviewed dependency closures; decoded containers
belong to the verified YAML implementation. Neither model authorizes arbitrary
subclasses, revivers, mutated values, or escaped containers.

The allowlist in `external_decoder_models.dart` verifies a SHA-256 fingerprint
over the complete non-SDK import/export/part closure. Each source contributes its
library URI, source URI, effective language version, and content digest. A changed,
missing, ambiguous, or unreadable source disables the model and retains the
conservative fallback. Absolute installation paths are not trusted identities.
Verification is cached only within the current analysis.

Before adding a fingerprint:

1. Review the defining decoder and its transitive implementation sources.
2. Verify that decoded values cannot dispatch to arbitrary workspace operators.
3. Use `tool/resolved_analysis/decoder_model_snapshot.dart` to inventory the
   source closure. Generating a digest alone is not approval.
4. Extend the positive and counterexample tests in
   `test/runner/resolved_decoders_test.dart`, including source changes, relocation,
   same-name impostors, mutation/escape, and vendored implementations.

Unrecognized versions remain supported through conservative analysis; they may
produce uncertainty warnings until their implementation has been reviewed.
