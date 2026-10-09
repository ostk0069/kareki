import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_scripts_');
    workspace.writePubspec(name: 'app', dependencies: {'args', 'path'});
    workspace.write('lib/api.dart', '''
void used({String? token}) => print(token);
void unused() {}
''');
  });
  tearDown(() => workspace.dispose());

  Future<RunResult> analyze() => KarekiRunner().analyze(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
    ),
  );

  for (final script in [
    'release.dart',
    'tool/release.dart',
    'tools/sub/release.dart',
  ]) {
    test(
      '$script retains imports, references and supplied arguments',
      () async {
        workspace.write(script, '''
import 'package:args/args.dart';
import 'package:app/api.dart';
void main() { print(ArgParser()); used(token: 'release'); }
''');
        final result = await analyze();
        expect(result.filesAnalyzed, 2);
        expect(result.analysisWarnings, isEmpty);
        expect(
          result.findings.map((f) => f.message),
          contains(contains("'unused'")),
        );
        expect(
          result.findings.where((f) => f.message.contains("'used'")),
          isEmpty,
        );
        expect(
          result.findings.where(
            (f) => f.ruleId == RuleId.unusedParameterOptional,
          ),
          isEmpty,
        );
        final deps = result.findings.where(
          (f) => f.ruleId == RuleId.unusedPubDependency,
        );
        expect(deps, hasLength(1));
        expect(deps.single.message, contains("'path'"));
        expect(
          result.findings.where((f) => f.filePath.endsWith(script)),
          isEmpty,
        );
      },
    );
  }

  test('tool helpers are not automatically rooted', () async {
    workspace.write(
      'tool/helper.dart',
      "import 'package:app/api.dart';\nvoid helper() => used();",
    );
    workspace.write('release.dart', 'void main() {}');
    final result = await analyze();
    expect(result.findings.map((f) => f.message), contains(contains("'used'")));
    expect(
      result.findings.map((f) => f.message),
      contains(contains("'helper'")),
    );
  });

  test(
    'ordinary hidden source directories still contribute references',
    () async {
      workspace.write('release.dart', '''
import 'tool/.internal/helper.dart';
void main() => helper();
''');
      workspace.write('tool/.internal/helper.dart', '''
import 'package:app/api.dart';
void helper() => used(token: 'provided');
''');
      final result = await analyze();
      expect(result.filesAnalyzed, 3);
      expect(result.analysisWarnings, isEmpty);
      expect(
        result.findings.where((f) => f.message.contains("'used'")),
        isEmpty,
      );
      expect(
        result.findings.where((f) => f.message.contains("'helper'")),
        isEmpty,
      );
    },
  );

  test('prunes build caches and respects nested package ownership', () async {
    workspace.write('pubspec.yaml', '''
name: app
environment:
  sdk: '>=3.10.0 <4.0.0'
workspace: [tools/child]
dependencies:
  args: any
''');
    workspace.write('tools/child/pubspec.yaml', '''
name: child
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  args: any
''');
    workspace.write(
      'tools/child/release.dart',
      "import 'package:args/args.dart';\nvoid main() => print(ArgParser());",
    );
    for (final dir in ['tool/build', 'tools/.dart_tool', 'tool/.git']) {
      workspace.write('$dir/ignored.dart', 'not valid Dart code');
    }
    workspace.write('release.dart', 'void main() {}');
    final result = await analyze();
    expect(result.filesAnalyzed, 3);
    expect(result.packagesAnalyzed, 2);
    expect(result.analysisWarnings, isEmpty);
    final deps = result.findings.where(
      (f) => f.ruleId == RuleId.unusedPubDependency,
    );
    expect(deps, hasLength(1));
    expect(deps.single.packageName, 'app');
  });
}
