import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_directives_');
    workspace.writePubspec(dependencies: {'collection', 'meta'});
  });

  tearDown(() => workspace.dispose());

  test('conditional directives and parts do not produce false positives', () {
    workspace.write('lib/api.dart', '''
import 'stub.dart' if (dart.library.html) 'browser.dart';
export 'package:meta/meta.dart'
    if (dart.library.io) 'package:collection/collection.dart';
part 'src/api_part.dart';

String platformName() => platformNameImpl;
''');
    workspace.write('lib/stub.dart', '''
const platformNameImpl = 'stub';
''');
    workspace.write('lib/browser.dart', '''
const platformNameImpl = 'browser';
''');
    workspace.write('lib/src/api_part.dart', '''
part of '../api.dart';

String partValue() => 'part';
''');
    workspace.write('bin/main.dart', '''
import 'package:runner_fixture/api.dart';

void main() => print(platformName());
''');

    final result = KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );
    final unusedFiles = result.findings
        .where((finding) => finding.ruleId == RuleId.unusedFile)
        .map((finding) => p.basename(finding.filePath));

    expect(unusedFiles, isNot(contains('stub.dart')));
    expect(unusedFiles, isNot(contains('browser.dart')));
    expect(unusedFiles, isNot(contains('api_part.dart')));
    expect(
      result.findings.where(
        (finding) => finding.ruleId == RuleId.unusedPubDependency,
      ),
      isEmpty,
    );
  });
}
