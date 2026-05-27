// Runs kareki against example/ and asserts every rule fires exactly
// once. Wired into CI so the example stays a faithful demo of every
// detector kareki ships.
//
// Usage: dart run tool/verify_example.dart

import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';

Future<void> main() async {
  final result = await Process.run(Platform.resolvedExecutable, const [
    'run',
    'bin/kareki.dart',
    '--root',
    'example',
    '--format',
    'json',
  ]);

  if (result.exitCode != 1) {
    stderr.writeln(
      'verify_example: expected exit code 1 (findings present), '
      'got ${result.exitCode}.',
    );
    stderr.writeln('stdout:\n${result.stdout}');
    stderr.writeln('stderr:\n${result.stderr}');
    exit(1);
  }

  final Map<String, dynamic> decoded;
  try {
    decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } on FormatException catch (e) {
    stderr.writeln('verify_example: failed to parse JSON output: $e');
    stderr.writeln('stdout:\n${result.stdout}');
    exit(1);
  }

  final findings = (decoded['findings'] as List).cast<Map<String, dynamic>>();
  final counts = <String, int>{};
  for (final f in findings) {
    final id = f['ruleId'] as String;
    counts[id] = (counts[id] ?? 0) + 1;
  }

  final problems = <String>[];
  for (final rule in RuleId.all) {
    final n = counts[rule] ?? 0;
    if (n != 1) {
      problems.add('  - $rule: expected 1, got $n');
    }
  }
  final unknown = counts.keys.toSet().difference(RuleId.all);
  for (final rule in unknown) {
    problems.add('  - $rule: unexpected rule id (count ${counts[rule]})');
  }

  if (problems.isNotEmpty) {
    stderr.writeln('verify_example: example/ no longer demonstrates every');
    stderr.writeln('rule exactly once. Update example/ or this verifier.');
    stderr.writeln(problems.join('\n'));
    stderr.writeln('\nFull findings:\n${result.stdout}');
    exit(1);
  }

  stdout.writeln(
    'verify_example: OK — ${RuleId.all.length} rule(s) each detected once.',
  );
}
