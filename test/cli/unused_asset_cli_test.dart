import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/cli/cli.dart';
import 'package:kareki/src/doctor/doctor_finding.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_asset_cli_');
    workspace.write('pubspec.yaml', '''
name: runner_fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
flutter:
  assets:
    - assets/
  fonts:
    - family: ExampleFont
      fonts:
        - asset: fonts/example.ttf
''');
    workspace.write('assets/used.png', 'image');
    workspace.write('assets/dead.png', 'image');
    workspace.write(
      'lib/main.dart',
      "void main() { print('assets/used.png'); }",
    );
  });
  tearDown(() => workspace.dispose());

  Future<({int exitCode, String output, String errors})> run(
    List<String> args,
  ) async {
    final output = _BufferStdout();
    final errors = _BufferStdout();
    final code = await IOOverrides.runZoned(
      () => runCli(args, workingDirectory: workspace.path),
      stdout: () => output,
      stderr: () => errors,
    );
    return (
      exitCode: code,
      output: output.buffer.toString(),
      errors: errors.buffer.toString(),
    );
  }

  test('CLI accepts the rule and reports JSON pubspec locations', () async {
    final result = await run(['--rule', 'unused_asset', '--format', 'json']);
    expect(result.exitCode, 1, reason: result.errors);
    final json = jsonDecode(result.output) as Map<String, dynamic>;
    final findings = (json['findings'] as List).cast<Map<String, dynamic>>();
    expect(findings, hasLength(2));
    expect(
      findings.every(
        (f) => f['ruleId'] == 'unused_asset' && f['file'] == 'pubspec.yaml',
      ),
      isTrue,
    );
    expect(
      (await run(['--rule', 'unused_asset'])).output,
      contains('[unused_asset] pubspec.yaml:'),
    );
    workspace.write('kareki-config.yaml', 'ignore:\n  rules: [unused_asset]\n');
    expect((await run(['--rule', 'unused_asset'])).exitCode, 0);
  });

  test(
    'baseline suppresses assets and keeps IDs stable after pubspec movement',
    () async {
      final written = await run([
        '--rule',
        'unused_asset',
        '--baseline',
        'baseline.json',
        '--write-baseline',
      ]);
      expect(written.exitCode, 0, reason: written.errors);
      final pubspec = File(p.join(workspace.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync('\n${pubspec.readAsStringSync()}');
      final suppressed = await run([
        '--rule',
        'unused_asset',
        '--baseline',
        'baseline.json',
      ]);
      expect(suppressed.exitCode, 0);
      expect(suppressed.errors, contains('2 suppressed by baseline'));
    },
  );

  test('doctor recognizes live asset path and family exclusions', () async {
    workspace.write('kareki-config.yaml', '''
exclude:
  files: [assets/dead.png]
  names: [ExampleFont, ghost]
''');
    final result = await DoctorRunner().run(
      DoctorRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );
    expect(
      result.findings.where((f) => f.kind == DoctorIssueKind.unusedExclude),
      isEmpty,
    );
    expect(
      result.findings
          .where((f) => f.kind == DoctorIssueKind.unusedExcludeName)
          .map((f) => f.subject),
      ['ghost'],
    );
    workspace.write(
      'kareki-config.yaml',
      'exclude:\n  names: [assets/dead.png, ExampleFont, ghost]\n',
    );
    final names = await DoctorRunner().run(
      DoctorRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );
    expect(
      names.findings
          .where((f) => f.kind == DoctorIssueKind.unusedExcludeName)
          .map((f) => f.subject),
      ['ghost'],
    );
  });

  test('doctor recognizes pubspec exclusions', () async {
    workspace.write(
      'kareki-config.yaml',
      'exclude:\n  files: [pubspec.yaml]\n',
    );
    final result = await DoctorRunner().run(
      DoctorRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );
    expect(
      result.findings.where((f) => f.kind == DoctorIssueKind.unusedExclude),
      isEmpty,
    );
  });
}

class _BufferStdout implements Stdout {
  final buffer = StringBuffer();
  @override
  void write(Object? object) => buffer.write(object);
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
