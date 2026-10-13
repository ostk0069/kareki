// Representative integration cases start fresh Dart VMs; detailed failure
// and baseline cases exercise the same CLI in process with captured output.
// Shared CI runners need more than the default 30 seconds for multi-run cases.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/cli/cli.dart';
import 'package:kareki/src/doctor/doctor_finding.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/l10n_workspace.dart';
import '../support/test_workspace.dart';

typedef _CliResult = ({int exitCode, String stdout, String stderr});

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_l10n_cli_');
    writeL10n(workspace);
  });
  tearDown(() => workspace.dispose());

  Future<_CliResult> run(List<String> arguments) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
      p.join(Directory.current.path, 'bin', 'kareki.dart'),
      ...arguments,
    ], workingDirectory: workspace.path);
    // Stop subprocesses before the workspace teardown, including on timeout.
    addTearDown(() async {
      process.kill();
      await process.exitCode;
    });
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    return (exitCode: exitCode, stdout: await stdout, stderr: await stderr);
  }

  Future<_CliResult> runInProcess(List<String> arguments) async {
    final output = _BufferStdout();
    final errors = _BufferStdout();
    final code = await IOOverrides.runZoned(
      () => runCli(arguments, workingDirectory: workspace.path),
      stdout: () => output,
      stderr: () => errors,
    );
    return (
      exitCode: code,
      stdout: output.buffer.toString(),
      stderr: errors.buffer.toString(),
    );
  }

  test('rule filtering, JSON locations and CLI exit codes 0/1', () async {
    final result = await run(['--rule', 'unused_l10n', '--format', 'json']);
    expect(result.exitCode, 1, reason: result.stderr);
    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final findings = (json['findings'] as List).cast<Map<String, dynamic>>();
    expect(findings, hasLength(2));
    expect(findings.map((f) => f['ruleId']).toSet(), {'unused_l10n'});
    expect(findings.map((f) => f['file']).toSet(), {'lib/l10n/app_en.arb'});
    final text = await run(['--rule', 'unused_l10n']);
    expect(text.stdout, contains('[unused_l10n] lib/l10n/app_en.arb:1:'));
    workspace.write('kareki-config.yaml', 'exclude:\n  names: [used, dead]\n');
    expect((await run(['--rule', 'unused_l10n'])).exitCode, 0);
  });

  test('baseline suppresses keys and doctor detects stale entries', () async {
    final written = await runInProcess([
      '--rule',
      'unused_l10n',
      '--baseline',
      'baseline.json',
      '--write-baseline',
    ]);
    expect(written.exitCode, 0, reason: written.stderr);
    expect(
      (await runInProcess([
        '--rule',
        'unused_l10n',
        '--baseline',
        'baseline.json',
      ])).exitCode,
      0,
    );
    workspace.write(
      'lib/main.dart',
      "import 'l10n/app_localizations.dart';\nvoid main() { print(AppLocalizations.of(Object()).used); }",
    );
    workspace.write('kareki-config.yaml', 'baseline: baseline.json\n');
    final doctor = await DoctorRunner().run(
      DoctorRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );
    expect(
      doctor.findings.where(
        (f) => f.kind == DoctorIssueKind.unusedBaselineEntry,
      ),
      hasLength(1),
    );
  });

  for (final failure in [
    'missing-output',
    'bad-arb',
    'stale-api',
    'missing-bootstrap',
  ]) {
    test(
      '$failure returns 2 and cannot publish or overwrite baseline',
      () async {
        switch (failure) {
          case 'missing-output':
            File(
              p.join(workspace.path, 'lib/l10n/app_localizations.dart'),
            ).deleteSync();
          case 'bad-arb':
            workspace.write('lib/l10n/app_en.arb', '{');
          case 'stale-api':
            workspace.write('lib/l10n/app_en.arb', '{"newKey":"New"}');
          case 'missing-bootstrap':
            Directory(
              p.join(workspace.path, '.dart_tool'),
            ).deleteSync(recursive: true);
        }
        const original = '{"version":1,"findings":[]}\n';
        workspace.write('baseline.json', original);
        // Keep a real exit-2 subprocess; the other failure variants exercise
        // the same error boundary without recompiling the CLI each time.
        final result =
            await (failure == 'missing-output' ? run : runInProcess)([
              '--rule',
              'unused_l10n',
              '--format',
              'json',
              '--baseline',
              'baseline.json',
              '--write-baseline',
            ]);
        expect(result.exitCode, 2, reason: result.stderr);
        expect(result.stdout, isEmpty);
        expect(result.stderr, contains('kareki:'));
        expect(result.stderr, isNot(contains('Unhandled exception')));
        expect(
          File(p.join(workspace.path, 'baseline.json')).readAsStringSync(),
          original,
        );
        File(p.join(workspace.path, 'baseline.json')).deleteSync();
        expect(
          (await runInProcess([
            '--rule',
            'unused_l10n',
            '--baseline',
            'baseline.json',
            '--write-baseline',
          ])).exitCode,
          2,
        );
        expect(
          File(p.join(workspace.path, 'baseline.json')).existsSync(),
          isFalse,
        );
      },
    );
  }

  test(
    'doctor recognizes ARB excludes and live/stale key name suppressions',
    () async {
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  names: [dead, ghost]\n  files: ["**/app_en.arb"]\n',
      );
      final excluded = await DoctorRunner().run(
        DoctorRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
        ),
      );
      expect(
        excluded.findings.where((f) => f.kind == DoctorIssueKind.unusedExclude),
        isEmpty,
      );
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  names: [dead, ghost]\n',
      );
      final result = await DoctorRunner().run(
        DoctorRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
        ),
      );
      expect(
        result.findings
            .where((f) => f.kind == DoctorIssueKind.unusedExcludeName)
            .map((f) => f.subject),
        ['ghost'],
      );
    },
  );

  test('unknown key usage cannot create or overwrite a baseline', () async {
    workspace.write(
      'lib/main.dart',
      "import 'l10n/app_localizations.dart';\nvoid main() { final value = AppLocalizations.of(Object()); print(value.used); print(value); }",
    );
    const original = '{"version":1,"findings":[]}\n';
    workspace.write('baseline.json', original);
    for (final existing in [true, false]) {
      if (!existing) File(p.join(workspace.path, 'baseline.json')).deleteSync();
      final result = await (existing ? run : runInProcess)([
        '--rule',
        'unused_l10n',
        '--baseline',
        'baseline.json',
        '--write-baseline',
      ]);
      expect(result.exitCode, 2, reason: result.stderr);
      expect(result.stderr, contains('1 used, 0 unused, 1 unknown'));
      expect(result.stderr, contains('cannot write baseline'));
      expect(result.stdout, isEmpty);
      final baseline = File(p.join(workspace.path, 'baseline.json'));
      expect(baseline.existsSync(), existing);
      if (existing) expect(baseline.readAsStringSync(), original);
    }
  });

  test(
    'baseline protection depends on unknown keys, not warning presence alone',
    () async {
      const imports = "import 'l10n/app_localizations.dart';\n";
      workspace.write(
        'lib/main.dart',
        '${imports}void main() { print(AppLocalizations.of(Object())); }',
      );
      const original = '{"version":1,"findings":[]}\n';
      workspace.write('baseline.json', original);
      final args = [
        '--root',
        workspace.path,
        '--rule',
        'unused_l10n',
        '--baseline',
        'baseline.json',
        '--write-baseline',
      ];
      expect((await runInProcess(args)).exitCode, 2);
      expect(
        File(p.join(workspace.path, 'baseline.json')).readAsStringSync(),
        original,
      );
      workspace.write(
        'lib/main.dart',
        '${imports}void main() { final value = AppLocalizations.of(Object()); print(value.used); print(value.dead); print(value); }',
      );
      expect((await runInProcess(args)).exitCode, 0);
      final baseline = Baseline.load(p.join(workspace.path, 'baseline.json'));
      expect(baseline, isNotNull);
    },
  );

  test('doctor skips semantic cleanup after uncertain l10n access', () async {
    workspace.write('kareki-config.yaml', 'exclude:\n  names: [ghost]\n');
    workspace.write(
      'lib/main.dart',
      'void main() { dynamic value = Object(); print(value.used); }',
    );
    final result = await run(['doctor', '--format', 'json']);
    expect(result.exitCode, 2, reason: result.stderr);
    expect(result.stderr, contains('Semantic doctor checks skipped'));
    expect(result.stdout, isNot(contains(DoctorIssueKind.unusedExcludeName)));
  });
  test(
    'doctor distinguishes live declaration-name exclusions from stale names',
    () async {
      workspace.write('lib/api.dart', 'void deadFunction() {}');
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  names: [deadFunction, ghost]\n',
      );
      final result = await DoctorRunner().run(
        DoctorRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
        ),
      );
      expect(
        result.findings
            .where((f) => f.kind == DoctorIssueKind.unusedExcludeName)
            .map((f) => f.subject),
        ['ghost'],
      );
    },
  );
}

// Only the text-writing surface used by the CLI is supported. Unexpected I/O
// operations throw through noSuchMethod instead of silently losing output.
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
