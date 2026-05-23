import 'dart:convert';

import 'package:kareki/src/doctor/doctor_finding.dart';

/// Renders the results of `kareki doctor` to a string.
abstract class DoctorReporter {
  String render(List<DoctorFinding> findings);
}

/// Human-friendly text output for `kareki doctor`.
class TextDoctorReporter implements DoctorReporter {
  @override
  String render(List<DoctorFinding> findings) {
    if (findings.isEmpty) {
      return 'kareki doctor: configuration is healthy — no issues found.';
    }
    final buffer = StringBuffer()
      ..writeln('kareki doctor — configuration health check.')
      ..writeln();

    // Pad kind tags so subjects line up.
    final maxKindLen = findings
        .map((f) => f.kind.length)
        .reduce((a, b) => a > b ? a : b);

    for (final f in findings) {
      final tag = '[${f.kind}]'.padRight(maxKindLen + 2);
      final line = StringBuffer('$tag ${f.subject}');
      if (f.detail != null) {
        line.write('  (${f.detail})');
      }
      buffer.writeln(line);
    }
    buffer
      ..writeln()
      ..writeln('${findings.length} issue(s) found.');
    return buffer.toString();
  }
}

/// Machine-readable JSON output for `kareki doctor`.
class JsonDoctorReporter implements DoctorReporter {
  @override
  String render(List<DoctorFinding> findings) {
    final payload = {
      'version': 1,
      'tool': 'kareki-doctor',
      'findings': [
        for (final f in findings)
          {
            'kind': f.kind,
            'subject': f.subject,
            if (f.detail != null) 'detail': f.detail,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
