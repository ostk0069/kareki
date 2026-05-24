import 'dart:convert';
import 'dart:io';

import 'package:kareki/src/model/finding.dart';
import 'package:path/path.dart' as p;

/// Snapshot of accepted findings. A finding present in the baseline is
/// hidden from CLI output, so teams can adopt kareki on a large
/// codebase without first deleting every existing finding.
///
/// Stored on disk as JSON keyed by `(ruleId, stableId)`. The `stableId`
/// is normalized so that the absolute workspace path is replaced with
/// `<root>` — the baseline file is portable across machines and CI
/// checkouts as long as the workspace layout matches.
class Baseline {
  Baseline._(this._keys);

  /// In-memory baseline; mostly useful for tests.
  factory Baseline.fromFindings(
    List<Finding> findings, {
    required String rootPath,
  }) {
    return Baseline._({
      for (final f in findings) _keyFor(f, rootPath: rootPath),
    });
  }

  final Set<String> _keys;

  /// Number of entries in the baseline.
  int get length => _keys.length;

  /// `true` when this finding is recorded in the baseline and should
  /// therefore be suppressed from output.
  bool contains(Finding finding, {required String rootPath}) {
    return _keys.contains(_keyFor(finding, rootPath: rootPath));
  }

  /// Returns the subset of baseline keys that did not match any
  /// finding in [findings]. Used by `kareki doctor` to flag baseline
  /// entries that no longer correspond to a real finding.
  Set<String> staleKeys(List<Finding> findings, {required String rootPath}) {
    final hit = {for (final f in findings) _keyFor(f, rootPath: rootPath)};
    return _keys.difference(hit);
  }

  /// Load a baseline from [path]. Returns `null` when the file does
  /// not exist (a missing baseline is not an error — it just means no
  /// findings have been accepted yet).
  static Baseline? load(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return Baseline._(<String>{});
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw FormatException("Baseline file '$path' is not a JSON object.");
    }
    final findings = decoded['findings'];
    if (findings is! List) return Baseline._(<String>{});
    final keys = <String>{};
    for (final entry in findings) {
      if (entry is! Map) continue;
      final ruleId = entry['ruleId']?.toString();
      final stableId = entry['stableId']?.toString();
      if (ruleId == null || stableId == null) continue;
      keys.add('$ruleId|$stableId');
    }
    return Baseline._(keys);
  }

  /// Serialize [findings] to [path] in the canonical baseline format.
  /// Entries are sorted by `(ruleId, stableId)` so the file is stable
  /// across runs and produces clean diffs.
  static void write(
    String path,
    List<Finding> findings, {
    required String rootPath,
  }) {
    final entries = [
      for (final f in findings)
        {
          'ruleId': f.ruleId,
          'stableId': _normalizeStableId(f.stableId, rootPath: rootPath),
          'file': p.relative(f.filePath, from: rootPath),
          'message': f.message,
        },
    ];
    entries.sort((a, b) {
      final byRule = a['ruleId']!.compareTo(b['ruleId']!);
      if (byRule != 0) return byRule;
      return a['stableId']!.compareTo(b['stableId']!);
    });
    final payload = {'version': 1, 'tool': 'kareki', 'findings': entries};
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }

  static String _keyFor(Finding f, {required String rootPath}) {
    return '${f.ruleId}|${_normalizeStableId(f.stableId, rootPath: rootPath)}';
  }

  /// Strip the workspace root from any absolute path embedded in a
  /// `stableId`, so the baseline file is portable across machines.
  static String _normalizeStableId(
    String stableId, {
    required String rootPath,
  }) {
    final normalizedRoot = p.normalize(rootPath);
    if (normalizedRoot.isEmpty) return stableId;
    final withSep = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';
    return stableId.replaceAll(withSep, '<root>/');
  }
}
