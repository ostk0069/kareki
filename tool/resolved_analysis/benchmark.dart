import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';

/// Read-only benchmark. Run each measurement in a fresh process.
/// Usage: `dart tool/resolved_analysis/benchmark.dart ROOT [doctor]`
/// JSON is written to stdout; redirect it outside the target checkout.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.length > 2 ||
      (arguments.length == 2 && arguments[1] != 'doctor')) {
    stderr.writeln('Usage: benchmark.dart ROOT [doctor]');
    exitCode = 64;
    return;
  }
  final root = Directory(arguments[0]).absolute.path;
  final doctor = arguments.length == 2;
  final watch = Stopwatch()..start();
  final report = <String, Object?>{
    'mode': 'resolved',
    'doctor': doctor,
    'runtime': Platform.version,
    'root': root,
  };
  try {
    final config = KarekiConfig.load(root);
    if (doctor) {
      final result = await DoctorRunner().analyze(
        DoctorRequest(rootPath: root, config: config),
      );
      report['warnings'] = result.analysisWarnings;
      if (result.analysisWarnings.isNotEmpty) {
        report['status'] = 'incomplete';
        exitCode = 2;
      }
      report['findings'] = [
        for (final finding in result.findings)
          {
            'kind': finding.kind,
            'subject': finding.subject,
            'detail': finding.detail,
          },
      ];
    } else {
      final result = await KarekiRunner().analyze(
        RunRequest(
          rootPath: root,
          config: config,
          enabledRules: {
            RuleId.unusedElement,
            RuleId.testOnlyUsed,
            RuleId.unusedParameterOptional,
          },
        ),
      );
      report['packagesAnalyzed'] = result.packagesAnalyzed;
      report['filesAnalyzed'] = result.filesAnalyzed;
      report['warnings'] = result.analysisWarnings;
      report['findings'] =
          (jsonDecode(JsonReporter().render(result.findings, rootPath: root))
              as Map<String, dynamic>)['findings'];
    }
    report.putIfAbsent('status', () => 'complete');
  } on Object catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = error.toString();
    report['stack'] = stack.toString();
    exitCode = 2;
  }
  report['elapsedMs'] = watch.elapsedMilliseconds;
  report['maxRssBytes'] = ProcessInfo.maxRss;
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
