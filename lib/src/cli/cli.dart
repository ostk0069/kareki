import 'dart:io';

import 'package:args/args.dart';

import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/reporter/reporter.dart';
import 'package:kareki/src/runner.dart';

/// Entry point used by both `bin/kareki.dart` and tests.
int runCli(List<String> arguments, {required String workingDirectory}) {
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
  final format = _parseFormat(formatName);
  if (format == null) {
    stderr.writeln("kareki: unknown format '$formatName'.");
    return 64;
  }

  final packagesArg = (args['packages'] as List<String>?) ?? const [];
  final packages = packagesArg.isEmpty ? null : packagesArg.toSet();
  final rulesArg = (args['rule'] as List<String>?) ?? const [];
  final rules = rulesArg.isEmpty ? null : rulesArg.toSet();
  if (rules != null) {
    final unknown = rules.difference(RuleId.all);
    if (unknown.isNotEmpty) {
      stderr.writeln("kareki: unknown rule(s): ${unknown.join(', ')}");
      return 64;
    }
  }

  final request = RunRequest(
    rootPath: rootPath,
    config: config,
    includePackages: packages,
    enabledRules: rules,
    strictDependencies: args['strict'] as bool,
  );

  final result = KarekiRunner().run(request);
  final reporter = _reporterFor(format);
  stdout.writeln(reporter.render(result.findings, rootPath: rootPath));

  if (format == OutputFormat.text) {
    stderr.writeln(
      'kareki: analyzed ${result.filesAnalyzed} file(s) across '
      '${result.packagesAnalyzed} package(s) in '
      '${result.elapsed.inMilliseconds}ms.',
    );
  }

  return result.findings.isEmpty ? 0 : 1;
}

OutputFormat? _parseFormat(String name) {
  switch (name) {
    case 'text':
      return OutputFormat.text;
    case 'json':
      return OutputFormat.json;
  }
  return null;
}

Reporter _reporterFor(OutputFormat format) {
  switch (format) {
    case OutputFormat.text:
      return TextReporter();
    case OutputFormat.json:
      return JsonReporter();
  }
}

const String _usageHeader = '''
kareki — multi-package dead code detector for Dart and Flutter monorepos.

Usage: kareki [options]
''';

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
    ..addMultiOption(
      'packages',
      help: 'Restrict analysis to these package names (repeatable).',
    )
    ..addMultiOption(
      'rule',
      help:
          'Enable only these rule ids (repeatable). '
          'Defaults to all rules.',
    )
    ..addFlag(
      'strict',
      help:
          'Treat dev_dependencies the same as dependencies '
          'for unused_pub_dependency.',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this usage information.',
      negatable: false,
    );
}
