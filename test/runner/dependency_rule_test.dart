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

  test(
    'native plugin metadata keeps build dependencies without imports',
    () async {
      workspace.writePubspec(
        dependencies: {'native_ffi', 'native_registered', 'ordinary'},
        devDependencies: {'dev_ffi', 'test'},
      );
      for (final name in [
        'native_ffi',
        'dev_ffi',
        'native_registered',
        'ordinary',
      ]) {
        final declaration = name == 'ordinary'
            ? 'dartPluginClass: Ordinary'
            : name == 'native_registered'
            ? 'pluginClass: NativePlugin'
            : 'ffiPlugin: true';
        workspace.write('vendor/$name/pubspec.yaml', '''
name: $name
flutter:
  plugin:
    platforms:
      linux:
        $declaration
''');
      }
      final result = await KarekiRunner().run(
        RunRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
          enabledRules: {RuleId.unusedPubDependency},
          strictDependencies: true,
        ),
      );
      expect(
        result.findings.map((f) => f.message),
        containsAll([
          contains("Dependency 'ordinary'"),
          contains("Dependency 'test'"),
        ]),
      );
      expect(result.findings, hasLength(2));
      // Metadata is reread on the next run, not cached across analyses.
      workspace.write('vendor/native_ffi/pubspec.yaml', 'name: native_ffi\n');
      final next = await KarekiRunner().run(
        RunRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
          enabledRules: {RuleId.unusedPubDependency},
        ),
      );
      expect(
        next.findings.map((f) => f.message),
        contains(contains("Dependency 'native_ffi'")),
      );
    },
  );

  test('strict mode adds unused dev dependencies only', () async {
    Future<RunResult> run({bool strict = false}) => KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
        enabledRules: {RuleId.unusedPubDependency},
        strictDependencies: strict,
      ),
    );

    final defaultMessages = (await run()).findings.map(
      (finding) => finding.message,
    );
    final strictMessages = (await run(
      strict: true,
    )).findings.map((finding) => finding.message);

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
