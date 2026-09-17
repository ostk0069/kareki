import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_generated_');
    workspace.writePubspec();
  });

  tearDown(() => workspace.dispose());

  test('excluded code keeps the APIs it references alive', () {
    workspace.write('lib/api.dart', '''
class KeptByGenerated {}
class TrulyUnused {}

void configure({String? token}) => print(token);
''');
    workspace.write('lib/model.g.dart', '''
import 'api.dart';

KeptByGenerated createModel() => KeptByGenerated();
void configureGeneratedModel() => configure(token: 'generated');
''');
    workspace.write('bin/main.dart', 'void main() {}\n');

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
            finding.message.contains("'KeptByGenerated'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'TrulyUnused'"),
      ),
      isTrue,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'token'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedFile &&
            finding.filePath.endsWith('model.g.dart'),
      ),
      isFalse,
    );
  });
}
