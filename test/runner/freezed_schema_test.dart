import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_freezed_');
    workspace.writePubspec(name: 'app');
    workspace.write(
      'vendor/freezed_annotation/pubspec.yaml',
      'name: freezed_annotation\n',
    );
    workspace.write('vendor/freezed_annotation/lib/freezed_annotation.dart', '''
class Freezed { const Freezed(); }
const freezed = Freezed();
''');
    workspace.write('lib/model.dart', '''
import 'package:freezed_annotation/freezed_annotation.dart';
part 'model.freezed.dart';
@freezed
abstract class Model {
  const factory Model.dynamic({String? token}) = GeneratedModel;
  factory Model.manual() => const GeneratedModel();
}
@Freezed()
abstract class Other { const factory Other.variant() = GeneratedOther; }
class Freezed { const Freezed(); }
@Freezed()
abstract class Homonym { const factory Homonym.variant() = ManualTarget; }
class ManualTarget implements Homonym { const ManualTarget(); }
''');
    // Keep the real annotation explicitly prefixed in this same-name test.
    workspace.write('lib/other.dart', '''
import 'package:freezed_annotation/freezed_annotation.dart' as actual;
@actual.Freezed()
abstract class Prefixed { const factory Prefixed.variant() = Target; }
class Target implements Prefixed { const Target(); }
''');
    workspace.write('lib/model.freezed.dart', '''
part of 'model.dart';
class GeneratedModel implements Model {
  const GeneratedModel({String? token});
}
class GeneratedOther implements Other { const GeneratedOther(); }
''');
    workspace.write('bin/main.dart', '''
import 'package:app/model.dart';
void main() { print(const GeneratedModel(token: 'provided')); print(const ManualTarget()); }
''');
  });
  tearDown(() => workspace.dispose());

  Future<RunResult> analyze() => KarekiRunner().analyze(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: {RuleId.unusedElement, RuleId.testOnlyUsed},
    ),
  );

  test(
    'keeps actual Freezed factories without retaining homonyms or bodies',
    () async {
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      final messages = result.findings.map((f) => f.message);
      expect(messages, isNot(contains(contains("'Model.dynamic'"))));
      expect(messages, isNot(contains(contains("'Prefixed.variant'"))));
      expect(messages, contains(contains("'Model.manual'")));
      expect(messages, contains(contains("'Homonym.variant'")));
    },
  );

  test('disabled and replaced presets do not add factory edges', () async {
    for (final config in [
      'keep_alive_annotations:\n  presets: [meta]\n',
      'custom_presets:\n  freezed:\n    keep_alive_annotations: []\n',
    ]) {
      workspace.write('kareki-config.yaml', config);
      expect(
        (await analyze()).findings.map((f) => f.message),
        contains(contains("'Model.dynamic'")),
      );
    }
  });
}
