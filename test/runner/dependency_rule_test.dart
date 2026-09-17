import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_dependencies_');
    workspace.writePubspec(
      dependencies: {'collection'},
      devDependencies: {'test'},
    );
    workspace.write('bin/main.dart', 'void main() {}\n');
  });

  tearDown(() => workspace.dispose());

  test('strict mode adds unused dev dependencies only', () {
    RunResult run({bool strict = false}) => KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
        enabledRules: {RuleId.unusedPubDependency},
        strictDependencies: strict,
      ),
    );

    final defaultMessages = run().findings.map((finding) => finding.message);
    final strictMessages = run(
      strict: true,
    ).findings.map((finding) => finding.message);

    expect(defaultMessages, contains(contains("Dependency 'collection'")));
    expect(defaultMessages, isNot(contains(contains("Dependency 'test'"))));
    expect(
      strictMessages,
      containsAll(<dynamic>[
        contains("Dependency 'collection'"),
        contains("Dependency 'test'"),
      ]),
    );
  });
}
