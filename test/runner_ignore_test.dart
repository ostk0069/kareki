import 'dart:io';

import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Build a minimal pub workspace under [root] with a single `app`
/// package containing the given files. Mirrors the helper in
/// `test/doctor/doctor_runner_test.dart` but pared down to a single
/// package.
void _scaffold(String root, {required Map<String, String> files}) {
  File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
    'name: _workspace_root\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ">=3.6.0 <4.0.0"\n'
    'workspace:\n'
    '  - app\n',
  );
  final pkgRoot = p.join(root, 'app');
  Directory(pkgRoot).createSync(recursive: true);
  File(p.join(pkgRoot, 'pubspec.yaml')).writeAsStringSync(
    'name: app\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ">=3.6.0 <4.0.0"\n'
    'resolution: workspace\n',
  );
  for (final entry in files.entries) {
    final path = p.join(pkgRoot, entry.key);
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(entry.value);
  }
}

RunResult _run(String root) => KarekiRunner().run(
  RunRequest(rootPath: root, config: KarekiConfig.load(root)),
);

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('kareki_runner_ignore_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('per-line `// kareki: ignore=...` suppression', () {
    test('standalone directive above a class suppresses unused_element', () {
      _scaffold(
        tempRoot.path,
        files: {
          'bin/main.dart': 'void main() {}\n',
          'lib/dead.dart':
              "// kareki: ignore=unused_element\n"
              'class Dead {}\n'
              '\n'
              'class StillDead {}\n',
        },
      );
      final findings = _run(tempRoot.path).findings;
      final dead = findings
          .where((f) => f.ruleId == RuleId.unusedElement)
          .map((f) => f.message)
          .toList();
      expect(
        dead.any((m) => m.contains("'Dead'")),
        isFalse,
        reason: 'Dead should be suppressed by the per-line directive',
      );
      expect(
        dead.any((m) => m.contains("'StillDead'")),
        isTrue,
        reason: 'StillDead is on a different line — must still be flagged',
      );
    });

    test('trailing directive on the same line suppresses unused_element', () {
      _scaffold(
        tempRoot.path,
        files: {
          'bin/main.dart': 'void main() {}\n',
          'lib/dead.dart': 'class Dead {} // kareki: ignore=unused_element\n',
        },
      );
      final findings = _run(tempRoot.path).findings;
      expect(
        findings.any(
          (f) =>
              f.ruleId == RuleId.unusedElement && f.message.contains("'Dead'"),
        ),
        isFalse,
      );
    });

    test('directive by symbol name suppresses only that symbol', () {
      _scaffold(
        tempRoot.path,
        files: {
          'bin/main.dart': 'void main() {}\n',
          'lib/dead.dart':
              "// kareki: ignore=Dead\n"
              'class Dead {}\n'
              '\n'
              'class Other {}\n',
        },
      );
      final dead = _run(tempRoot.path).findings
          .where((f) => f.ruleId == RuleId.unusedElement)
          .map((f) => f.message)
          .toList();
      expect(dead.any((m) => m.contains("'Dead'")), isFalse);
      expect(dead.any((m) => m.contains("'Other'")), isTrue);
    });

    test('per-line directive suppresses unused_parameter', () {
      _scaffold(
        tempRoot.path,
        files: {
          'bin/main.dart':
              "import 'package:app/lib.dart';\n"
              'void main() => Foo.bar(1);\n',
          // `unused` parameter would normally be flagged; the trailing
          // directive on the parameter's line suppresses it.
          'lib/lib.dart':
              'class Foo {\n'
              '  static void bar(\n'
              '    int used,\n'
              '    {int? unused} // kareki: ignore=unused_parameter\n'
              '  ) {\n'
              '    used;\n'
              '  }\n'
              '}\n',
        },
      );
      final findings = _run(tempRoot.path).findings;
      expect(
        findings.any(
          (f) =>
              f.ruleId == RuleId.unusedParameter &&
              f.message.contains("'unused'"),
        ),
        isFalse,
      );
    });
  });
}
