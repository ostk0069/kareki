import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  group('unused_parameter', () {
    test('flags body-unused parameters and skips exemptions', () {
      final root = fixturePath('unused_parameter');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      final messages = result.findings
          .where((finding) => finding.ruleId == RuleId.unusedParameter)
          .map((finding) => finding.message);

      for (final expectedName in [
        "'unusedOne'",
        "'unusedTwo'",
        "'unusedFive'",
      ]) {
        expect(
          messages.any((message) => message.contains(expectedName)),
          isTrue,
          reason: '$expectedName should be flagged',
        );
      }
      for (final exemptName in [
        "'_'",
        "'__'",
        "'key'",
        "'value'",
        "'unusedThree'",
        "'unusedFour'",
        "'width'",
        "'height'",
        "'used'",
        "'a'",
        "'name'",
        "'title'",
        "'raw'",
        "'rects'",
      ]) {
        expect(
          messages.any((message) => message.contains(exemptName)),
          isFalse,
          reason: '$exemptName must not be flagged',
        );
      }
    });

    test('can be disabled by the rule filter', () {
      final root = fixturePath('unused_parameter');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedElement, RuleId.unusedFile},
        ),
      );

      expect(
        result.findings.any(
          (finding) => finding.ruleId == RuleId.unusedParameter,
        ),
        isFalse,
      );
    });
  });
}
