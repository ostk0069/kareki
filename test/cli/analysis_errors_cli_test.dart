import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_analysis_errors_cli_');
    workspace.write('pubspec.yaml', 'name: app\nflutter:\n  generate: true\n');
    workspace.write('bin/main.dart', 'void main() {}');
    workspace.write('l10n.yaml', 'arb-dir: [\n');
  });
  tearDown(() => workspace.dispose());

  Future<ProcessResult> run(
    List<String> arguments,
  ) => Process.run(Platform.resolvedExecutable, [
    '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
    p.join(Directory.current.path, 'bin', 'kareki.dart'),
    ...arguments,
  ], workingDirectory: workspace.path);

  for (final mode in <String, List<String>>{
    'normal analysis': [],
    'syntax-only analysis': ['--rule', 'unused_parameter'],
    'doctor': ['doctor'],
  }.entries) {
    test('${mode.key} reports malformed l10n YAML with exit 2', () async {
      final result = await run([...mode.value, '--format', 'json']);
      expect(result.exitCode, 2, reason: '${result.stderr}');
      // Incomplete analysis must not publish a partial/empty findings report.
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('l10n.yaml'));
      expect(result.stderr, contains('Expected node content'));
      expect(result.stderr, isNot(contains('Unhandled exception')));
    });
  }

  test('malformed l10n YAML cannot overwrite an existing baseline', () async {
    const original = '{"existing": "baseline"}\n';
    workspace.write('baseline.json', original);
    final result = await run([
      '--baseline',
      'baseline.json',
      '--write-baseline',
    ]);
    expect(result.exitCode, 2, reason: '${result.stderr}');
    expect(
      File(p.join(workspace.path, 'baseline.json')).readAsStringSync(),
      original,
    );
  });

  test('help describes packages as a reporting filter', () async {
    final result = await run(['--help']);
    expect(result.exitCode, 0);
    // The argument formatter can wrap either sentence across lines.
    final help = result.stdout.toString().replaceAll(RegExp(r'\s+'), ' ');
    expect(help, contains('Report findings only for these package names'));
    expect(
      help,
      contains(
        'References are still collected across the discovered workspace',
      ),
    );
    expect(help, isNot(contains('Restrict analysis')));
  });
}
