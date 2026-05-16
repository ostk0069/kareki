import 'dart:convert';

import 'package:kareki/src/model/finding.dart';
import 'package:path/path.dart' as p;

/// Renders a list of [Finding]s to a string. Implementations are free
/// to produce any format — kareki ships [TextReporter] and
/// [JsonReporter] for the CLI's `--format text|json` options. Custom
/// reporters can be plugged in via the programmatic API
/// (`package:kareki/kareki.dart`).
abstract class Reporter {
  /// Format [findings] for output. When [rootPath] is supplied, file
  /// paths are reported relative to it; otherwise absolute paths are
  /// emitted.
  String render(List<Finding> findings, {String? rootPath});
}

/// Human-friendly text output, grouped by package then sorted by rule
/// id, file path, and line number. Used by the CLI when `--format=text`
/// (the default).
class TextReporter implements Reporter {
  @override
  String render(List<Finding> findings, {String? rootPath}) {
    if (findings.isEmpty) {
      return 'kareki: no unused declarations found.';
    }
    final buffer = StringBuffer();
    final byPackage = <String, List<Finding>>{};
    for (final finding in findings) {
      byPackage.putIfAbsent(finding.packageName, () => []).add(finding);
    }
    final packageNames = byPackage.keys.toList()..sort();
    for (final pkg in packageNames) {
      buffer.writeln('• Package: $pkg');
      final entries = byPackage[pkg]!
        ..sort((a, b) {
          final ruleCmp = a.ruleId.compareTo(b.ruleId);
          if (ruleCmp != 0) return ruleCmp;
          final fileCmp = a.filePath.compareTo(b.filePath);
          if (fileCmp != 0) return fileCmp;
          return a.line.compareTo(b.line);
        });
      for (final f in entries) {
        final path = rootPath != null
            ? p.relative(f.filePath, from: rootPath)
            : f.filePath;
        buffer.writeln('  [${f.ruleId}] $path:${f.line}:${f.column}');
        buffer.writeln('    ${f.message}');
      }
    }
    buffer.writeln();
    buffer.writeln(
      'kareki: ${findings.length} finding(s) across '
      '${packageNames.length} package(s).',
    );
    return buffer.toString();
  }
}

/// Machine-readable JSON output. Emits a top-level object with
/// `version`, `tool`, and `findings` (a list of objects mirroring
/// [Finding]). Used by the CLI when `--format=json`.
class JsonReporter implements Reporter {
  @override
  String render(List<Finding> findings, {String? rootPath}) {
    final payload = {
      'version': 1,
      'tool': 'kareki',
      'findings': [
        for (final f in findings)
          {
            'ruleId': f.ruleId,
            'severity': f.severity.name,
            'message': f.message,
            'package': f.packageName,
            'file': rootPath != null
                ? p.relative(f.filePath, from: rootPath)
                : f.filePath,
            'line': f.line,
            'column': f.column,
            'length': f.length,
            'stableId': f.stableId,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
