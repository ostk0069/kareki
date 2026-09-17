import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  group('test_only_used', () {
    test('flags production symbols referenced only by tests', () {
      final root = fixturePath('test_only_used');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.testOnlyUsed &&
              finding.message.contains("'testOnlyFn'"),
        ),
        isTrue,
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.testOnlyUsed &&
              finding.message.contains("'TestOnlyClass'"),
        ),
        isTrue,
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.testOnlyUsed &&
              finding.message.contains("'productionFn'"),
        ),
        isFalse,
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedElement &&
              finding.message.contains("'testOnlyFn'"),
        ),
        isFalse,
      );
    });

    test('does not flag overrides of production-reachable types', () {
      final root = fixturePath('test_only_used');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.testOnlyUsed &&
              finding.message.contains("'ProductionHandler.applyTo'"),
        ),
        isFalse,
        reason:
            'Virtual dispatch is not visible to the simple-name graph, so '
            'an override on a reachable type must not be a false positive.',
      );
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedElement &&
              finding.message.contains("'ProductionHandler.applyTo'"),
        ),
        isFalse,
      );
    });

    test('can be disabled by the rule filter', () {
      final root = fixturePath('test_only_used');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedElement, RuleId.unusedFile},
        ),
      );

      expect(
        result.findings.any((finding) => finding.ruleId == RuleId.testOnlyUsed),
        isFalse,
      );
    });
  });
}
