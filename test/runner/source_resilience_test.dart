import 'dart:io';

import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/reachability/resolved_reachability.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_source_resilience_');
    workspace.writePubspec();
  });

  tearDown(() => workspace.dispose());

  test('unreadable l10n text fails with an analysis diagnostic', () async {
    workspace.write('pubspec.yaml', 'name: app\nflutter:\n  generate: true\n');
    final config = File(p.join(workspace.path, 'l10n.yaml'));
    config.writeAsBytesSync([0xff]);
    await expectLater(
      KarekiRunner().run(
        RunRequest(
          rootPath: workspace.path,
          config: KarekiConfig.defaults(),
          enabledRules: {'unused_parameter'},
        ),
      ),
      throwsA(
        isA<ResolvedAnalysisException>().having(
          (error) => error.diagnostics.join('\n'),
          'diagnostic',
          contains('l10n.yaml'),
        ),
      ),
    );
  });

  test(
    'invalid l10n YAML fails even a syntax-only run with its path',
    () async {
      workspace.write(
        'pubspec.yaml',
        'name: app\nflutter:\n  generate: true\n',
      );
      workspace.write('l10n.yaml', 'arb-dir: [\n');
      workspace.write('bin/main.dart', 'void main() {}');
      await expectLater(
        KarekiRunner().run(
          RunRequest(
            rootPath: workspace.path,
            config: KarekiConfig.defaults(),
            enabledRules: {'unused_parameter'},
          ),
        ),
        throwsA(
          isA<ResolvedAnalysisException>().having(
            (error) => error.diagnostics.join('\n'),
            'diagnostic',
            allOf(contains('l10n.yaml'), contains('Expected node content')),
          ),
        ),
      );
    },
  );

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
