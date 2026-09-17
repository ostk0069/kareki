import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_source_resilience_');
    workspace.writePubspec();
  });

  tearDown(() => workspace.dispose());

  test('an incomplete source does not hide findings in valid files', () {
    workspace.write('lib/broken.dart', '''
class Broken {
  void unfinished(
''');
    workspace.write('lib/api.dart', 'class KnownUnused {}\n');
    workspace.write('bin/main.dart', 'void main() {}\n');

    final result = KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );

    expect(result.filesAnalyzed, 3);
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'KnownUnused'"),
      ),
      isTrue,
    );
  });
}
