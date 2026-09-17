import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_primary_constructor_');
    workspace.write('pubspec.yaml', '''
name: primary_constructor_workspace
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
workspace:
  - app
''');
    workspace.write('app/pubspec.yaml', '''
name: app
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
resolution: workspace
''');
  });

  tearDown(() => workspace.dispose());

  test('primary constructors participate in all applicable rules', () {
    workspace.write('app/lib/api.dart', '''
class Point.named(final int usedField, final int unusedField, int unusedInput) {
  int read() => usedField;
}

enum Status({int? code, int? unusedCode}) {
  active(code: 1),
  inactive();
}

Point makePoint() => Point.named(1, 2, 3);
''');
    workspace.write('app/bin/main.dart', '''
import 'package:app/api.dart';

void main() {
  print(makePoint().read());
  print(Status.active);
}
''');

    final result = KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );

    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'usedField'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'Point.unusedField'"),
      ),
      isTrue,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameter &&
            finding.message.contains("'unusedInput'"),
      ),
      isTrue,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'code'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'unusedCode'"),
      ),
      isTrue,
    );
  });
}
