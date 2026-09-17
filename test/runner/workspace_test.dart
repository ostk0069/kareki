import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  group('workspace analysis', () {
    test('single package detects unused elements, files, and dependencies', () {
      final root = fixturePath('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      expect(result.packagesAnalyzed, 1);
      expect(result.filesAnalyzed, greaterThan(0));
      expect(
        result.findings.map((finding) => finding.ruleId).toSet(),
        containsAll(<String>{
          RuleId.unusedElement,
          RuleId.unusedFile,
          RuleId.unusedPubDependency,
        }),
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedElement &&
              finding.message.contains('UnusedClass'),
        ),
        isTrue,
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedFile &&
              finding.filePath.endsWith('orphan.dart'),
        ),
        isTrue,
      );
      expect(
        result.findings
            .where((finding) => finding.ruleId == RuleId.unusedPubDependency)
            .map((finding) => finding.message),
        containsAll(<dynamic>[contains("'meta'"), contains("'collection'")]),
      );
    });

    test('used symbols are not flagged', () {
      final root = fixturePath('single_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      final flaggedNames = result.findings
          .where((finding) => finding.ruleId == RuleId.unusedElement)
          .map((finding) => finding.message);

      expect(
        flaggedNames.any((message) => message.contains("'addOne'")),
        isFalse,
      );
      expect(
        flaggedNames.any((message) => message.contains("'UsedThing'")),
        isFalse,
      );
    });

    test('cross-package reachability works', () {
      final root = fixturePath('multi_package');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      expect(result.packagesAnalyzed, 3);
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedElement &&
              finding.message.contains("'hello'"),
        ),
        isFalse,
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedElement &&
              finding.message.contains("'unreferencedAcrossPackages'"),
        ),
        isTrue,
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedFile &&
              finding.filePath.endsWith('unused_pkg.dart'),
        ),
        isTrue,
      );
    });

    test('rule filter restricts emitted rules', () {
      final root = fixturePath('single_package');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedFile},
        ),
      );

      expect(result.findings.map((finding) => finding.ruleId).toSet(), {
        RuleId.unusedFile,
      });
    });

    test('package filter restricts analysis to one package', () {
      final root = fixturePath('multi_package');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          includePackages: {'used_pkg'},
        ),
      );

      expect(result.packagesAnalyzed, 1);
      for (final finding in result.findings) {
        expect(finding.packageName, 'used_pkg');
      }
    });
  });
}
