import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _fixture(String name) =>
    p.join(p.dirname(p.fromUri(Uri.parse('test'))), 'test', 'fixtures', name);

void main() {
  group('KarekiRunner', () {
    test('single package: detects unused element, file, and dependency', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      expect(result.packagesAnalyzed, 1);
      expect(result.filesAnalyzed, greaterThan(0));

      final ruleIds = result.findings.map((f) => f.ruleId).toSet();
      expect(
        ruleIds,
        containsAll(<String>{
          RuleId.unusedElement,
          RuleId.unusedFile,
          RuleId.unusedPubDependency,
        }),
      );

      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.unusedElement &&
              f.message.contains('UnusedClass'),
        ),
        isTrue,
        reason: 'UnusedClass should be flagged as unused_element',
      );
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.unusedFile &&
              f.filePath.endsWith('orphan.dart'),
        ),
        isTrue,
        reason: 'orphan.dart should be flagged as unused_file',
      );
      expect(
        result.findings
            .where((f) => f.ruleId == RuleId.unusedPubDependency)
            .map((f) => f.message)
            .toList(),
        containsAll(<dynamic>[contains("'meta'"), contains("'collection'")]),
      );
    });

    test('used symbols are not flagged', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      final flaggedNames = result.findings
          .where((f) => f.ruleId == RuleId.unusedElement)
          .map((f) => f.message)
          .toList();
      expect(flaggedNames.any((m) => m.contains("'addOne'")), isFalse);
      expect(flaggedNames.any((m) => m.contains("'UsedThing'")), isFalse);
    });

    test('multi-package: cross-package reachability works', () {
      final root = _fixture('multi_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      expect(result.packagesAnalyzed, 3);

      // hello() from used_pkg is called by app/bin/main.dart — must NOT be
      // flagged.
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.unusedElement && f.message.contains("'hello'"),
        ),
        isFalse,
      );

      // unreferencedAcrossPackages() exists in used_pkg but is referenced
      // from nowhere — should be flagged.
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.unusedElement &&
              f.message.contains("'unreferencedAcrossPackages'"),
        ),
        isTrue,
      );

      // unused_pkg/lib/unused_pkg.dart is never imported.
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.unusedFile &&
              f.filePath.endsWith('unused_pkg.dart'),
        ),
        isTrue,
      );
    });

    test('--rule filter restricts emitted rules', () {
      final root = _fixture('single_package');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedFile},
        ),
      );
      final ruleIds = result.findings.map((f) => f.ruleId).toSet();
      expect(ruleIds, {RuleId.unusedFile});
    });

    test('package filter restricts analysis to a single package', () {
      final root = _fixture('multi_package');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          includePackages: {'used_pkg'},
        ),
      );
      expect(result.packagesAnalyzed, 1);
      for (final f in result.findings) {
        expect(f.packageName, 'used_pkg');
      }
    });
  });
}
