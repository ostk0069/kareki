import 'dart:convert';

import 'package:kareki/src/dependency/native_plugin_dependencies.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  late PackageInfo app;
  setUp(() {
    workspace = TestWorkspace.create('kareki_native_', bootstrap: false);
    app = PackageInfo(
      name: 'app',
      rootPath: '${workspace.path}/apps/app',
      pubspecPath: '${workspace.path}/apps/app/pubspec.yaml',
      dependencies: {'native'},
      devDependencies: {},
    );
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'native', 'rootUri': '../vendor/native'},
        ],
      }),
    );
  });
  tearDown(() => workspace.dispose());

  Set<String> check() =>
      NativePluginDependencies().forPackage(app, strict: false);

  test(
    'finds parent workspace config and resolves relative installed roots',
    () {
      workspace.write('vendor/native/pubspec.yaml', '''
name: native
flutter:
  plugin:
    platforms:
      ios:
        ffiPlugin: true
''');
      expect(check(), {'native'});
      // An owning package's configuration takes precedence over the workspace.
      workspace.write(
        'apps/app/.dart_tool/package_config.json',
        '{"packages": []}',
      );
      expect(check(), isEmpty);
    },
  );

  test('supports legacy native registration', () {
    workspace.write('vendor/native/pubspec.yaml', '''
name: native
flutter:
  plugin:
    androidPackage: example.plugin
    pluginClass: NativePlugin
''');
    expect(check(), {'native'});
  });

  test('missing or invalid metadata does not hide ordinary dependencies', () {
    expect(check(), isEmpty);
    for (final metadata in [
      '[]',
      'name: different',
      'name: native',
      'name: native\nflutter: []',
      'name: native\nflutter:\n  plugin: []',
      'name: native\nflutter:\n  plugin:\n    platforms:\n      ios:\n        ffiPlugin: false',
      'name: native\nflutter:\n  plugin:\n    platforms:\n      ios:\n        pluginClass: ""',
      'name: native\nflutter:\n  plugin:\n    platforms:\n      web:\n        dartPluginClass: DartOnly',
      'invalid: [',
    ]) {
      workspace.write('vendor/native/pubspec.yaml', metadata);
      expect(check(), isEmpty, reason: metadata);
    }
  });

  test('malformed or non-file package configurations are not trusted', () {
    for (final configuration in [
      'invalid',
      '[]',
      '{"packages": {}}',
      '{"packages": [null, {"name": "native"}]}',
      '{"packages": [{"name": "native", "rootUri": "https://example.invalid/"}]}',
    ]) {
      workspace.write('.dart_tool/package_config.json', configuration);
      expect(check(), isEmpty);
    }
  });
}
