import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('kareki_doctor_cli_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<({int exitCode, String stdout, String stderr})> runDoctor(
    List<String> args,
  ) async {
    // dart test runs with cwd = package root, so bin/kareki.dart resolves
    // relative to it.
    final entry = p.join(Directory.current.path, 'bin', 'kareki.dart');
    final result = await Process.run('dart', [
      'run',
      entry,
      'doctor',
      ...args,
    ], workingDirectory: tempRoot.path);
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  void _scaffoldMinimalApp({String? karekiConfig}) {
    File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsStringSync(
      'name: app\n'
      'publish_to: none\n'
      'environment:\n'
      '  sdk: ">=3.6.0 <4.0.0"\n',
    );
    Directory(p.join(tempRoot.path, 'lib')).createSync();
    File(
      p.join(tempRoot.path, 'lib', 'main.dart'),
    ).writeAsStringSync('void main() {}\n');
    if (karekiConfig != null) {
      File(
        p.join(tempRoot.path, 'kareki-config.yaml'),
      ).writeAsStringSync(karekiConfig);
    }
  }

  test('exits 0 and prints "healthy" on a clean config', () async {
    _scaffoldMinimalApp();
    final r = await runDoctor([]);
    expect(r.exitCode, 0, reason: 'stdout: ${r.stdout}\nstderr: ${r.stderr}');
    expect(r.stdout, contains('healthy'));
  });

  test(
    'exits 1 and reports the dead glob when exclude.files is stale',
    () async {
      _scaffoldMinimalApp(
        karekiConfig:
            'version: 1\n'
            'exclude:\n'
            '  files:\n'
            '    - "**/*.legacy.dart"\n',
      );
      final r = await runDoctor([]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('unused-exclude'));
      expect(r.stdout, contains('**/*.legacy.dart'));
    },
  );

  test('--format json emits machine-readable output', () async {
    _scaffoldMinimalApp(
      karekiConfig:
          'version: 1\n'
          'ignore:\n'
          '  packages:\n'
          '    - missing_pkg\n',
    );
    final r = await runDoctor(['--format', 'json']);
    expect(r.exitCode, 1);
    final decoded = jsonDecode(r.stdout) as Map<String, dynamic>;
    expect(decoded['tool'], 'kareki-doctor');
    final findings = decoded['findings'] as List;
    expect(findings, hasLength(1));
    expect((findings.first as Map)['kind'], 'unused-ignore-package');
    expect((findings.first as Map)['subject'], 'missing_pkg');
  });
}
