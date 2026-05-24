import 'dart:io';

import 'package:kareki/src/baseline/baseline.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _fixture(String name) =>
    p.join(Directory.current.path, 'test', 'fixtures', name);

void main() {
  group('Baseline', () {
    test('write + load round-trips the same findings', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      expect(result.findings, isNotEmpty);

      final tmp = Directory.systemTemp.createTempSync('kareki_baseline_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = p.join(tmp.path, '.kareki-baseline.json');

      Baseline.write(path, result.findings, rootPath: root);
      final loaded = Baseline.load(path)!;

      expect(loaded.length, result.findings.length);
      for (final f in result.findings) {
        expect(loaded.contains(f, rootPath: root), isTrue);
      }
    });

    test('load returns null when the file does not exist', () {
      expect(Baseline.load('/no/such/file.json'), isNull);
    });

    test('filter suppresses baselined findings and keeps the rest', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      final unused = result.findings
          .where((f) => f.ruleId == RuleId.unusedElement)
          .toList();
      expect(unused, isNotEmpty);

      // Baseline only the unused_element findings.
      final baseline = Baseline.fromFindings(unused, rootPath: root);
      final remaining = result.findings
          .where((f) => !baseline.contains(f, rootPath: root))
          .toList();

      expect(remaining.any((f) => f.ruleId == RuleId.unusedElement), isFalse);
      expect(remaining.length, result.findings.length - unused.length);
    });

    test('serialized file is portable: paths use <root>/ placeholder', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      final tmp = Directory.systemTemp.createTempSync('kareki_baseline_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = p.join(tmp.path, '.kareki-baseline.json');
      Baseline.write(path, result.findings, rootPath: root);
      final raw = File(path).readAsStringSync();

      expect(raw, contains('<root>/'));
      expect(raw, isNot(contains(root)));
    });

    test('staleKeys reports entries no longer present in findings', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      expect(result.findings.length, greaterThan(1));

      final baseline = Baseline.fromFindings(result.findings, rootPath: root);
      final shortened = result.findings.sublist(1);
      final stale = baseline.staleKeys(shortened, rootPath: root);
      expect(stale, hasLength(1));
    });
  });
}
