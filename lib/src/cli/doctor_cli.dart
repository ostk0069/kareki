import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/doctor/doctor_reporter.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:kareki/src/reachability/resolved_reachability.dart';

const String _usageHeader = '''
kareki doctor — validate kareki-config.yaml against workspace state.

Reports stale `exclude.files` globs, `ignore.packages` entries pointing at
packages that no longer exist, `ignore.dependencies` entries pointing at
dependencies that are no longer declared in pubspec.yaml, and file-level
`// kareki: ignore_for_file=...` directives that suppress no finding.

Usage: kareki doctor [options]
''';

/// Entry point for `dart run kareki doctor ...`. [arguments] are the
/// arguments after the leading `doctor` token.
int runDoctor(List<String> arguments, {required String workingDirectory}) {
  return _runDoctor(
        arguments,
        workingDirectory: workingDirectory,
        asynchronous: false,
      )
      as int;
}

Future<int> runDoctorAsync(
  List<String> arguments, {
  required String workingDirectory,
}) async {
  return await _runDoctor(
    arguments,
    workingDirectory: workingDirectory,
    asynchronous: true,
  );
}

FutureOr<int> _runDoctor(
  List<String> arguments, {
  required String workingDirectory,
  required bool asynchronous,
}) {
  final parser = _buildArgParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('kareki: ${e.message}');
    stderr.writeln(parser.usage);
    return 64;
  }

  if (args['help'] as bool) {
    stdout.writeln(_usageHeader);
    stdout.writeln(parser.usage);
    return 0;
  }

  final rootPath = (args['root'] as String?) ?? workingDirectory;
  final KarekiConfig config;
  try {
    config = KarekiConfig.load(rootPath);
  } on FormatException catch (error) {
    stderr.writeln('kareki: $error');
    return 64;
  }
  final formatName = args['format'] as String?;
  final format = formatName == null
      ? config.output
      : OutputFormat.values.byName(formatName);
  final reporter = _reporterFor(format);

  final request = DoctorRequest(
    rootPath: rootPath,
    config: config,
    analysisMode: args['analysis-mode'] == null
        ? null
        : AnalysisMode.values.byName(args['analysis-mode'] as String),
  );
  if (asynchronous) return _analyzeAndReport(request, reporter);
  if (request.effectiveAnalysisMode == AnalysisMode.resolved) {
    stderr.writeln('kareki: resolved doctor requires runDoctorAsync.');
    return 64;
  }
  return _report(DoctorRunner().run(request), reporter);
}

Future<int> _analyzeAndReport(
  DoctorRequest request,
  DoctorReporter reporter,
) async {
  try {
    return _report(await DoctorRunner().analyze(request), reporter);
  } on ResolvedAnalysisException catch (error) {
    stderr.writeln('kareki: $error');
    return 2;
  }
}

int _report(DoctorResult result, DoctorReporter reporter) {
  for (final warning in result.analysisWarnings) {
    stderr.writeln('kareki doctor: $warning');
  }
  if (result.analysisWarnings.isNotEmpty &&
      result.findings.isEmpty &&
      reporter is TextDoctorReporter) {
    stdout.writeln('kareki doctor: incomplete — semantic checks were skipped.');
  } else {
    stdout.writeln(reporter.render(result.findings));
  }

  if (reporter is TextDoctorReporter) {
    stderr.writeln(
      'kareki doctor: completed in ${result.elapsed.inMilliseconds}ms.',
    );
  }

  if (result.analysisWarnings.isNotEmpty) return 2;
  return result.findings.isEmpty ? 0 : 1;
}

DoctorReporter _reporterFor(OutputFormat format) {
  switch (format) {
    case OutputFormat.text:
      return TextDoctorReporter();
    case OutputFormat.json:
      return JsonDoctorReporter();
  }
}

ArgParser _buildArgParser() {
  return ArgParser()
    ..addOption(
      'analysis-mode',
      allowed: ['legacy', 'resolved'],
      help: 'Analysis engine used to validate suppressions and baselines.',
    )
    ..addOption(
      'root',
      help: 'Workspace root directory (defaults to current directory).',
    )
    ..addOption(
      'format',
      abbr: 'f',
      help: 'Output format. Overrides kareki-config.yaml.',
      allowed: ['text', 'json'],
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this usage information.',
      negatable: false,
    );
}
