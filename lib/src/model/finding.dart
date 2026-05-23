/// Severity of a detection.
enum Severity {
  /// The finding represents something the user is expected to act on
  /// (delete, suppress, or otherwise resolve).
  warning,

  /// Diagnostic / metadata output that does not require action.
  info,
}

/// Rule identifiers emitted by kareki.
///
/// Constants are passed in CLI flags (`--rule <id>`), printed in
/// `Finding.ruleId`, and used in the `ignore.rules` config section.
class RuleId {
  const RuleId._();

  /// A public declaration is not referenced by anyone in the workspace.
  static const String unusedElement = 'unused_element';

  /// A `.dart` file is not imported, parted, or exported from anywhere.
  static const String unusedFile = 'unused_file';

  /// A package declared in `pubspec.yaml` is never imported in source.
  static const String unusedPubDependency = 'unused_pub_dependency';

  /// A production declaration is only reachable from test entry points
  /// (e.g. `*_test.dart`, files under `test/` or `integration_test/`).
  /// The declaration exists in `lib/` source but is never consumed by
  /// production code — its tests are testing something nobody uses.
  static const String testOnlyUsed = 'test_only_used';

  /// The complete set of rule ids emitted by kareki.
  static const Set<String> all = {
    unusedElement,
    unusedFile,
    unusedPubDependency,
    testOnlyUsed,
  };
}

/// A single detection result.
///
/// Findings are emitted from [KarekiRunner.run] inside [RunResult.findings]
/// and rendered via [Reporter].
class Finding {
  /// Creates a finding. End-users normally consume [Finding] instances
  /// produced by [KarekiRunner]; this constructor exists for custom
  /// reporters / tests.
  Finding({
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.packageName,
    required this.filePath,
    required this.line,
    required this.column,
    required this.length,
    required this.stableId,
  });

  /// One of [RuleId.all]. See [RuleId] for the canonical constants.
  final String ruleId;

  final Severity severity;

  /// Human-readable description of the finding.
  final String message;

  /// Name of the pub package the finding originates from.
  final String packageName;

  /// Absolute path of the source file the finding points at.
  final String filePath;

  /// 1-based line number of the finding location.
  final int line;

  /// 1-based column number of the finding location.
  final int column;

  /// Length of the offending source span, in characters. May be `0` for
  /// finding kinds that point at a whole file or pubspec entry.
  final int length;

  /// Stable identifier suitable for baseline diffs and SARIF
  /// `partialFingerprints`. Encodes package + file + symbol + kind so
  /// the same declaration produces the same id across runs even when
  /// surrounding lines are added or removed.
  final String stableId;
}
