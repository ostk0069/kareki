import 'dart:io';

import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/doctor/doctor_finding.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Build a minimal workspace under [root] containing one or more
/// packages. Each [packages] entry is a map from package name to a
/// map of relative file path → file content. A `pubspec.yaml` is
/// generated automatically when not provided.
void _scaffold(
  String root, {
  required Map<String, Map<String, String>> packages,
  Map<String, dynamic>? rootPubspec,
}) {
  // Root pub workspace pubspec.
  final rootPubspecYaml = StringBuffer()
    ..writeln('name: _workspace_root')
    ..writeln('publish_to: none')
    ..writeln('environment:')
    ..writeln('  sdk: ">=3.6.0 <4.0.0"')
    ..writeln('workspace:');
  for (final name in packages.keys) {
    rootPubspecYaml.writeln('  - $name');
  }
  if (rootPubspec != null) {
    for (final entry in rootPubspec.entries) {
      rootPubspecYaml.writeln('${entry.key}: ${entry.value}');
    }
  }
  File(
    p.join(root, 'pubspec.yaml'),
  ).writeAsStringSync(rootPubspecYaml.toString());

  for (final pkgEntry in packages.entries) {
    final pkgName = pkgEntry.key;
    final pkgRoot = p.join(root, pkgName);
    Directory(pkgRoot).createSync(recursive: true);
    var hasPubspec = false;
    for (final fileEntry in pkgEntry.value.entries) {
      final path = p.join(pkgRoot, fileEntry.key);
      Directory(p.dirname(path)).createSync(recursive: true);
      File(path).writeAsStringSync(fileEntry.value);
      if (fileEntry.key == 'pubspec.yaml') hasPubspec = true;
    }
    if (!hasPubspec) {
      File(p.join(pkgRoot, 'pubspec.yaml')).writeAsStringSync(
        'name: $pkgName\n'
        'publish_to: none\n'
        'environment:\n'
        '  sdk: ">=3.6.0 <4.0.0"\n'
        'resolution: workspace\n',
      );
    }
  }
}

void _writeKarekiConfig(String root, String contents) {
  File(p.join(root, 'kareki-config.yaml')).writeAsStringSync(contents);
}

DoctorRequest _request(String root) =>
    DoctorRequest(rootPath: root, config: KarekiConfig.load(root));

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('kareki_doctor_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('DoctorRunner', () {
    test('flags `exclude.files` globs that match no file in the workspace', () {
      _scaffold(
        tempRoot.path,
        packages: {
          'app': {'lib/main.dart': 'class A {}\n'},
        },
      );
      _writeKarekiConfig(tempRoot.path, '''
version: 1
exclude:
  files:
    - "**/*.legacy.dart"
    - "**/*.dart"
''');
      final result = DoctorRunner().run(_request(tempRoot.path));
      final dead = result.findings
          .where((f) => f.kind == DoctorIssueKind.unusedExclude)
          .map((f) => f.subject)
          .toList();
      expect(dead, contains('**/*.legacy.dart'));
      expect(
        dead,
        isNot(contains('**/*.dart')),
        reason: '**/*.dart should match main.dart in the workspace',
      );
    });

    test('flags `ignore.packages` entries pointing at unknown packages', () {
      _scaffold(
        tempRoot.path,
        packages: {
          'app': {'lib/main.dart': 'class A {}\n'},
        },
      );
      _writeKarekiConfig(tempRoot.path, '''
version: 1
ignore:
  packages:
    - app
    - wt_legacy_removed
''');
      final result = DoctorRunner().run(_request(tempRoot.path));
      final dead = result.findings
          .where((f) => f.kind == DoctorIssueKind.unusedIgnorePackage)
          .map((f) => f.subject)
          .toList();
      expect(dead, contains('wt_legacy_removed'));
      expect(dead, isNot(contains('app')));
    });

    test(
      'flags `ignore.dependencies` parent keys when the package is unknown',
      () {
        _scaffold(
          tempRoot.path,
          packages: {
            'app': {
              'pubspec.yaml':
                  'name: app\n'
                  'publish_to: none\n'
                  'environment:\n'
                  '  sdk: ">=3.6.0 <4.0.0"\n'
                  'resolution: workspace\n'
                  'dependencies:\n'
                  '  meta: ^1.10.0\n',
              'lib/main.dart': 'class A {}\n',
            },
          },
        );
        _writeKarekiConfig(tempRoot.path, '''
version: 1
ignore:
  dependencies:
    removed_pkg:
      - something
''');
        final result = DoctorRunner().run(_request(tempRoot.path));
        final dead = result.findings
            .where(
              (f) => f.kind == DoctorIssueKind.unusedIgnoreDependenciesPackage,
            )
            .map((f) => f.subject)
            .toList();
        expect(dead, contains('removed_pkg'));
      },
    );

    test('flags `ignore.dependencies` entries whose dep is not declared', () {
      _scaffold(
        tempRoot.path,
        packages: {
          'app': {
            'pubspec.yaml':
                'name: app\n'
                'publish_to: none\n'
                'environment:\n'
                '  sdk: ">=3.6.0 <4.0.0"\n'
                'resolution: workspace\n'
                'dependencies:\n'
                '  meta: ^1.10.0\n',
            'lib/main.dart': 'class A {}\n',
          },
        },
      );
      _writeKarekiConfig(tempRoot.path, '''
version: 1
ignore:
  dependencies:
    app:
      - meta
      - removed_dep
''');
      final result = DoctorRunner().run(_request(tempRoot.path));
      final findings = result.findings
          .where((f) => f.kind == DoctorIssueKind.unusedIgnoreDependency)
          .map((f) => f.subject)
          .toList();
      expect(findings, contains('app -> removed_dep'));
      expect(findings, isNot(contains('app -> meta')));
    });

    test('flags `ignore_for_file` directives that match no real finding', () {
      // The file ignores `test_only_used`, but nothing in the file would
      // ever trigger that rule (the only declaration is a private member,
      // and there are no test files referencing it). The ignore directive
      // is therefore dead.
      _scaffold(
        tempRoot.path,
        packages: {
          'app': {
            'pubspec.yaml':
                'name: app\n'
                'publish_to: none\n'
                'environment:\n'
                '  sdk: ">=3.6.0 <4.0.0"\n'
                'resolution: workspace\n',
            'bin/main.dart':
                "import 'package:app/used.dart';\n"
                'void main() => use();\n',
            'lib/used.dart':
                '// kareki: ignore_for_file=test_only_used\n'
                '// nothing in this file is actually test-only.\n'
                '\n'
                'void use() {}\n',
          },
        },
      );
      _writeKarekiConfig(tempRoot.path, '''
version: 1
''');
      final result = DoctorRunner().run(_request(tempRoot.path));
      final dead = result.findings
          .where((f) => f.kind == DoctorIssueKind.unusedIgnoreDirective)
          .toList();
      expect(dead, hasLength(1));
      expect(dead.first.detail, 'test_only_used');
      expect(dead.first.subject, endsWith('used.dart'));
    });

    test(
      'flags baseline entries whose stableId is no longer produced by '
      'any current finding',
      () {
        _scaffold(
          tempRoot.path,
          packages: {
            'app': {
              'pubspec.yaml':
                  'name: app\n'
                  'publish_to: none\n'
                  'environment:\n'
                  '  sdk: ">=3.6.0 <4.0.0"\n'
                  'resolution: workspace\n',
              'lib/main.dart': 'void main() {}\n',
              // Dead class that will be the live baseline entry.
              'lib/used.dart': 'class StillDead {}\n',
            },
          },
        );
        _writeKarekiConfig(tempRoot.path, '''
version: 1
baseline: .kareki-baseline.json
''');
        // Hand-craft a baseline with one entry that matches the dead
        // class and one entry that points at a class that no longer
        // exists.
        File(p.join(tempRoot.path, '.kareki-baseline.json')).writeAsStringSync('''
{
  "version": 1,
  "tool": "kareki",
  "findings": [
    {
      "ruleId": "unused_element",
      "stableId": "app|<root>/app/lib/used.dart||StillDead|classDecl",
      "file": "app/lib/used.dart",
      "message": "Unused public classDecl 'StillDead'."
    },
    {
      "ruleId": "unused_element",
      "stableId": "app|<root>/app/lib/used.dart||GhostClass|classDecl",
      "file": "app/lib/used.dart",
      "message": "Unused public classDecl 'GhostClass'."
    }
  ]
}
''');
        final result = DoctorRunner().run(_request(tempRoot.path));
        final stale = result.findings
            .where((f) => f.kind == DoctorIssueKind.unusedBaselineEntry)
            .toList();
        expect(stale, hasLength(1));
        expect(stale.single.subject, contains('GhostClass'));
        expect(stale.single.detail, 'baseline');
      },
    );

    test('healthy config reports no findings', () {
      _scaffold(
        tempRoot.path,
        packages: {
          'app': {
            'pubspec.yaml':
                'name: app\n'
                'publish_to: none\n'
                'environment:\n'
                '  sdk: ">=3.6.0 <4.0.0"\n'
                'resolution: workspace\n'
                'dependencies:\n'
                '  meta: ^1.10.0\n',
            'lib/main.dart': 'class A {}\n',
            'lib/foo.g.dart': '// generated\n',
          },
        },
      );
      _writeKarekiConfig(tempRoot.path, '''
version: 1
exclude:
  files:
    - "**/*.g.dart"
ignore:
  packages: []
  dependencies:
    app:
      - meta
''');
      final result = DoctorRunner().run(_request(tempRoot.path));
      expect(result.findings, isEmpty);
    });
  });
}
