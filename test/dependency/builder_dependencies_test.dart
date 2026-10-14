import 'dart:convert';

import 'package:kareki/src/dependency/builder_dependencies.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  late PackageInfo app;
  setUp(() {
    workspace = TestWorkspace.create('kareki_builders_', bootstrap: false);
    app = PackageInfo(
      name: 'app',
      rootPath: '${workspace.path}/apps/app',
      pubspecPath: '${workspace.path}/apps/app/pubspec.yaml',
      dependencies: {'generator'},
      devDependencies: {},
    );
  });
  tearDown(() => workspace.dispose());

  Set<String> check() => BuilderDependencies().forPackage(app);

  void configureGenerator() {
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'packages': [
          {'name': 'generator', 'rootUri': '../vendor/generator'},
        ],
      }),
    );
  }

  test('explicit builder references work without resolved metadata', () {
    workspace.write('apps/app/build.yaml', r'''
targets:
  $default:
    builders:
      generator: {}
      :local: {}
''');
    expect(check(), {'generator', 'app'});
  });

  test('malformed configuration does not exempt unreferenced dependencies', () {
    for (final configuration in [
      'invalid',
      '[]',
      '{"packages": {}}',
      '{"packages": [null, {"name": "generator"}]}',
      '{"packages": [{"name": "generator", "rootUri": "https://example.invalid/"}]}',
    ]) {
      workspace.write('.dart_tool/package_config.json', configuration);
      expect(check(), isEmpty, reason: configuration);
    }
  });

  test('invalid builder metadata never establishes automatic usage', () {
    configureGenerator();
    for (final metadata in [
      'invalid: [',
      '[]',
      'builders: []',
      'builders: {invalid: null}',
      'builders: {manual: {auto_apply: none}}',
      'builders: {invalid: {auto_apply: unknown}}',
      'builders: {"other:builder": {auto_apply: dependents}}',
    ]) {
      workspace.write('vendor/generator/build.yaml', metadata);
      expect(check(), isEmpty, reason: metadata);
    }
  });

  test(
    'owning package config takes precedence over ancestor configuration',
    () {
      configureGenerator();
      workspace.write('vendor/generator/build.yaml', '''
builders:
  :builder:
    auto_apply: dependents
''');
      expect(check(), {'generator'});
      workspace.write(
        'apps/app/.dart_tool/package_config.json',
        '{"packages": []}',
      );
      expect(check(), isEmpty);
    },
  );

  test('malformed target configuration cannot create explicit references', () {
    for (final configuration in [
      'invalid: [',
      '[]',
      'targets: {default: null}',
      'targets: {default: {builders: {1: {}}}}',
    ]) {
      workspace.write('apps/app/build.yaml', configuration);
      expect(check(), isEmpty, reason: configuration);
    }
  });
}
