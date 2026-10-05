import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  late KarekiConfig config;
  setUp(() {
    workspace = TestWorkspace.create('kareki_variants_');
    workspace.writePubspec();
    workspace.write('kareki-config.yaml', '''
exclude:
  parameter_names: [option]
''');
    workspace.write('lib/api.dart', '''
// kareki: ignore_for_file=unused_element
void dead() {}
void used({int option = 0}) { print(option); }
''');
    workspace.write('bin/main.dart', '''
import 'package:runner_fixture/api.dart';
void main() { used(); }
''');
    config = KarekiConfig.load(workspace.path);
  });
  tearDown(() => workspace.dispose());

  test('shared resolution preserves each reporting variant', () async {
    final requests = [
      RunRequest(rootPath: workspace.path, config: config),
      RunRequest(
        rootPath: workspace.path,
        config: config,
        enabledRules: {RuleId.unusedParameter, RuleId.unusedParameterOptional},
        disregardParameterNameExcludes: true,
      ),
      RunRequest(
        rootPath: workspace.path,
        config: config,
        disregardFileLevelIgnores: true,
      ),
    ];
    final runner = KarekiRunner();
    final batch = await runner.analyzeVariants(requests);
    for (var i = 0; i < requests.length; i++) {
      final independent = await runner.analyze(requests[i]);
      expect(
        batch[i].findings.map((f) => f.stableId),
        independent.findings.map((f) => f.stableId),
      );
      expect(batch[i].analysisWarnings, independent.analysisWarnings);
      expect(batch[i].filesAnalyzed, independent.filesAnalyzed);
    }
    expect(batch[0].findings, isEmpty);
    expect(batch[1].findings.single.stableId, contains('|optparam:option'));
    expect(batch[2].findings.single.message, contains("'dead'"));
  });

  test(
    'a later invocation sees source edits and resolution failures',
    () async {
      final runner = KarekiRunner();
      final request = RunRequest(
        rootPath: workspace.path,
        config: config,
        disregardParameterNameExcludes: true,
      );
      expect((await runner.analyze(request)).findings, hasLength(1));
      workspace.write('bin/main.dart', '''
import 'package:runner_fixture/api.dart';
void main() { used(option: 1); }
''');
      expect((await runner.analyze(request)).findings, isEmpty);
      workspace.write('lib/broken.dart', 'MissingType value = MissingType();');
      await expectLater(
        runner.analyzeVariants([request, request]),
        throwsA(isA<ResolvedAnalysisException>()),
      );
    },
  );

  test('empty batches and graph-free reporting variants', () async {
    final runner = KarekiRunner();
    expect(await runner.analyzeVariants([]), isEmpty);
    final results = await runner.analyzeVariants([
      RunRequest(
        rootPath: workspace.path,
        config: config,
        enabledRules: {RuleId.unusedPubDependency},
      ),
      RunRequest(
        rootPath: workspace.path,
        config: config,
        enabledRules: {RuleId.unusedFile},
      ),
    ]);
    expect(results, hasLength(2));
    expect(results.every((r) => r.findings.isEmpty), isTrue);
  });

  test('variants cannot mix source scopes or configurations', () async {
    final request = RunRequest(rootPath: workspace.path, config: config);
    for (final other in [
      RunRequest(rootPath: '${workspace.path}/other', config: config),
      RunRequest(rootPath: workspace.path, config: KarekiConfig.defaults()),
      RunRequest(
        rootPath: workspace.path,
        config: config,
        includePackages: {'runner_fixture'},
      ),
    ]) {
      await expectLater(
        KarekiRunner().analyzeVariants([request, other]),
        throwsArgumentError,
      );
    }
  });
}
