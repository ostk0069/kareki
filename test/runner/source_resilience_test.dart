import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/reachability/resolved_reachability.dart';
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

  test(
    'an incomplete source fails without returning partial findings',
    () async {
      workspace.write('lib/broken.dart', '''
class Broken {
  void unfinished(
''');
      workspace.write('lib/api.dart', 'class KnownUnused {}\n');
      workspace.write('bin/main.dart', 'void main() {}\n');

      await expectLater(
        KarekiRunner().run(
          RunRequest(
            rootPath: workspace.path,
            config: KarekiConfig.load(workspace.path),
          ),
        ),
        throwsA(isA<ResolvedAnalysisException>()),
      );
    },
  );
}
