import 'dart:io';

import 'package:args/args.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/doctor/doctor_reporter.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';

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
  final config = KarekiConfig.load(rootPath);

  final formatName = args['format'] as String? ?? config.output.name;
  final reporter = _reporterFor(formatName);
  if (reporter == null) {
    stderr.writeln("kareki: unknown format '$formatName'.");
    return 64;
  }

  final result = DoctorRunner().run(
    DoctorRequest(rootPath: rootPath, config: config),
  );
  stdout.writeln(reporter.render(result.findings));

  if (reporter is TextDoctorReporter) {
    stderr.writeln(
      'kareki doctor: completed in ${result.elapsed.inMilliseconds}ms.',
    );
  }

  return result.findings.isEmpty ? 0 : 1;
}

DoctorReporter? _reporterFor(String name) {
  switch (name) {
    case 'text':
      return TextDoctorReporter();
    case 'json':
      return JsonDoctorReporter();
  }
  return null;
}

ArgParser _buildArgParser() {
  return ArgParser()
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
