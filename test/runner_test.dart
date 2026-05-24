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

    test('test_only_used: production symbol referenced only by tests', () {
      final root = _fixture('test_only_used');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      // testOnlyFn lives in lib/ but only test/test_only_test.dart
      // references it → test_only_used.
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.testOnlyUsed &&
              f.message.contains("'testOnlyFn'"),
        ),
        isTrue,
        reason: 'testOnlyFn should be flagged as test_only_used',
      );
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.testOnlyUsed &&
              f.message.contains("'TestOnlyClass'"),
        ),
        isTrue,
        reason: 'TestOnlyClass should be flagged as test_only_used',
      );

      // productionFn is referenced from bin/main.dart → not flagged.
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.testOnlyUsed &&
              f.message.contains("'productionFn'"),
        ),
        isFalse,
        reason: 'productionFn is consumed by production code',
      );

      // test_only symbols are reachable (from test), so they must NOT be
      // emitted as plain unused_element.
      expect(
        result.findings.any(
          (f) =>
              f.ruleId == RuleId.unusedElement &&
              f.message.contains("'testOnlyFn'"),
        ),
        isFalse,
        reason: 'testOnlyFn is reachable from tests, not unused_element',
      );
    });

    test(
      'test_only_used: @override of a production-reachable type is not flagged',
      () {
        final root = _fixture('test_only_used');
        final result = KarekiRunner().run(
          RunRequest(rootPath: root, config: KarekiConfig.load(root)),
        );

        // ProductionHandler is instantiated in bin/main.dart and its
        // `applyTo` is invoked by name only in test code. Without the
        // @override exemption applied to test_only_used this would be
        // flagged; with the exemption it must NOT be.
        expect(
          result.findings.any(
            (f) =>
                f.ruleId == RuleId.testOnlyUsed &&
                f.message.contains("'ProductionHandler.applyTo'"),
          ),
          isFalse,
          reason:
              'ProductionHandler.applyTo is an @override of a '
              'production-reachable type — virtual dispatch is invisible '
              'to the simple-name BFS, so the test-only call must not '
              'cause a false positive.',
        );

        // It must also not be flagged as unused_element (the existing
        // @override exemption for unused_element should still hold).
        expect(
          result.findings.any(
            (f) =>
                f.ruleId == RuleId.unusedElement &&
                f.message.contains("'ProductionHandler.applyTo'"),
          ),
          isFalse,
        );
      },
    );

    test('test_only_used can be disabled via --rule filter', () {
      final root = _fixture('test_only_used');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedElement, RuleId.unusedFile},
        ),
      );
      expect(
        result.findings.any((f) => f.ruleId == RuleId.testOnlyUsed),
        isFalse,
      );
    });

    test(
      'unused_parameter: flags body-unused parameters and skips exemptions',
      () {
        final root = _fixture('unused_parameter');
        final result = KarekiRunner().run(
          RunRequest(rootPath: root, config: KarekiConfig.load(root)),
        );

        final unusedParamMessages = result.findings
            .where((f) => f.ruleId == RuleId.unusedParameter)
            .map((f) => f.message)
            .toList();

        // Each of these must be present.
        for (final expectedName in [
          "'unusedOne'",
          "'unusedTwo'",
          "'unusedFive'",
        ]) {
          expect(
            unusedParamMessages.any((m) => m.contains(expectedName)),
            isTrue,
            reason: '$expectedName should be flagged as unused_parameter',
          );
        }

        // None of these must be present.
        for (final exemptName in [
          // `_` and `__` placeholders
          "'_'",
          "'__'",
          // abstract method params
          "'key'",
          "'value'",
          // operator
          "'unusedThree'",
          // @override
          "'unusedFour'",
          // this.x
          "'width'",
          "'height'",
          // used params
          "'used'",
          "'a'",
          "'name'",
          "'title'",
          "'raw'",
          // GestureExclusion.setRects body is only `throw
          // UnimplementedError(...)` — stub idiom, must not be flagged.
          "'rects'",
        ]) {
          expect(
            unusedParamMessages.any((m) => m.contains(exemptName)),
            isFalse,
            reason: '$exemptName must not be flagged as unused_parameter',
          );
        }
      },
    );

    test('unused_parameter can be disabled via --rule filter', () {
      final root = _fixture('unused_parameter');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedElement, RuleId.unusedFile},
        ),
      );
      expect(
        result.findings.any((f) => f.ruleId == RuleId.unusedParameter),
        isFalse,
      );
    });

    test('unused_parameter_optional: flags optional params never passed at any '
        'call site and skips exemptions', () {
      final root = _fixture('unused_parameter_optional');
      final result = KarekiRunner().run(
        RunRequest(rootPath: root, config: KarekiConfig.load(root)),
      );

      final optionalMessages = result.findings
          .where((f) => f.ruleId == RuleId.unusedParameterOptional)
          .map((f) => f.message)
          .toList();

      // Each of these must be present.
      for (final expectedName in [
        // `port`: passed by no call site of `buildUrl`.
        "'port'",
        // `extra`: optional positional index 1 of `formatNumber`,
        // never reached.
        "'extra'",
        // `retryCount`: passed by no call site of `send`.
        "'retryCount'",
        // `endpoint`: unnamed `HttpClient` constructor's optional named
        // param, never passed.
        "'endpoint'",
        // `unusedTag`: optional named param of `Service.create`,
        // never passed.
        "'unusedTag'",
      ]) {
        expect(
          optionalMessages.any((m) => m.contains(expectedName)),
          isTrue,
          reason:
              '$expectedName should be flagged as '
              'unused_parameter_optional',
        );
      }

      // None of these must be present.
      for (final exemptName in [
        // `_` placeholder
        "'_'",
        // abstract method param
        "'unusedAbstractParam'",
        // this.x / this.y
        "'width'",
        "'height'",
        // passed params
        "'host'",
        "'timeout'",
        "'tag'",
        // Platform.open is a stub idiom — must not be flagged.
        "'url'",
      ]) {
        expect(
          optionalMessages.any((m) => m.contains(exemptName)),
          isFalse,
          reason:
              '$exemptName must not be flagged as '
              'unused_parameter_optional',
        );
      }
    });

    test('unused_parameter_optional can be disabled via --rule filter', () {
      final root = _fixture('unused_parameter_optional');
      final result = KarekiRunner().run(
        RunRequest(
          rootPath: root,
          config: KarekiConfig.load(root),
          enabledRules: {RuleId.unusedElement, RuleId.unusedFile},
        ),
      );
      expect(
        result.findings.any((f) => f.ruleId == RuleId.unusedParameterOptional),
        isFalse,
      );
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
