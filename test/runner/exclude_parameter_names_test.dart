import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_exclude_parameter_names_');
    workspace.writePubspec();
    workspace.write('kareki-config.yaml', '''
version: 1
exclude:
  parameter_names: [context]
''');
    workspace.write('lib/api.dart', '''
void render(Object context, Object other, Object unusedRequired) {
  print(other);
}

void configure({Object? context, Object? neverPassed}) {
  print(context);
  print(neverPassed);
}
''');
    workspace.write('bin/main.dart', '''
import 'package:runner_fixture/api.dart';

void main() {
  render(Object(), Object(), Object());
  configure();
}
''');
  });

  tearDown(() => workspace.dispose());

  test('suppresses matching names for both unused parameter rules', () {
    final config = KarekiConfig.load(workspace.path);
    expect(config.excludeParameterNames, {'context'});

    final findings = KarekiRunner()
        .run(RunRequest(rootPath: workspace.path, config: config))
        .findings;

    expect(
      findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameter &&
            finding.message.contains("'context'"),
      ),
      isFalse,
    );
    expect(
      findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'context'"),
      ),
      isFalse,
    );
    expect(
      findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameter &&
            finding.message.contains("'unusedRequired'"),
      ),
      isTrue,
      reason: 'non-matching parameter names must still be reported',
    );
    expect(
      findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'neverPassed'"),
      ),
      isTrue,
      reason: 'non-matching parameter names must still be reported',
    );
  });
}
