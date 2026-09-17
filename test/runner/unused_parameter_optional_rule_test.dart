import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  group('unused_parameter_optional', () {
    test('flags never-passed parameters and skips exemptions', () {
      final root = fixturePath('unused_parameter_optional');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );
      final messages = result.findings
          .where((finding) => finding.ruleId == RuleId.unusedParameterOptional)
          .map((finding) => finding.message);

      for (final expectedName in [
        "'port'",
        "'extra'",
        "'retryCount'",
        "'endpoint'",
        "'unusedTag'",
      ]) {
        expect(
          messages.any((message) => message.contains(expectedName)),
          isTrue,
          reason: '$expectedName should be flagged',
        );
      }
      for (final exemptName in [
        "'_'",
        "'unusedAbstractParam'",
        "'width'",
        "'height'",
        "'host'",
        "'timeout'",
        "'tag'",
        "'url'",
      ]) {
        expect(
          messages.any((message) => message.contains(exemptName)),
          isFalse,
          reason: '$exemptName must not be flagged',
        );
      }
    });

    test('can be disabled by the rule filter', () {
      final root = fixturePath('unused_parameter_optional');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedElement, RuleId.unusedFile},
        ),
      );

      expect(
        result.findings.any(
          (finding) => finding.ruleId == RuleId.unusedParameterOptional,
        ),
        isFalse,
      );
    });
  });
}
