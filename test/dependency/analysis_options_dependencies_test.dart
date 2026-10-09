import 'package:kareki/src/dependency/analysis_options_dependencies.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(
    () => workspace = TestWorkspace.create('kareki_options_', bootstrap: false),
  );
  tearDown(() => workspace.dispose());

  Set<String> check() => AnalysisOptionsDependencies().forPackage(
    PackageInfo(
      name: 'app',
      rootPath: '${workspace.path}/app',
      pubspecPath: '${workspace.path}/app/pubspec.yaml',
      dependencies: {},
      devDependencies: {},
    ),
    [
      DeclarationCollector().collect(
        path: '${workspace.path}/app/lib/sub/file.dart',
        packageName: 'app',
        content: '',
      ),
    ],
  );

  test('ancestor and nested options use lists and cyclic relative includes', () {
    workspace.write(
      'analysis_options.yaml',
      'include: [package:root/rules.yaml, null, "https://example.invalid/rules", "%"]',
    );
    workspace.write('app/lib/sub/analysis_options.yaml', 'include: rules.yaml');
    workspace.write(
      'app/lib/sub/rules.yaml',
      'include: [analysis_options.yaml, package:nested/rules.yaml]',
    );
    expect(check(), {'root', 'nested'});
  });

  test(
    'malformed configuration and options never exempt arbitrary packages',
    () {
      workspace.write(
        'app/analysis_options.yaml',
        'include: package:used/rules.yaml',
      );
      for (final config in [
        'broken',
        '[]',
        '{"packages": {}}',
        '{"packages": [null, {}]}',
      ]) {
        workspace.write('app/.dart_tool/package_config.json', config);
        expect(check(), {'used'});
      }
      for (final options in [
        'invalid: [',
        '[]',
        'analyzer: {}',
        'include: [null, package:invalid]',
      ]) {
        workspace.write('app/analysis_options.yaml', options);
        expect(check(), isEmpty);
      }
    },
  );
}
