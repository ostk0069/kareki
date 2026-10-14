import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_dependency_usage_');
    workspace.writePubspec(name: 'app');
    workspace.write('lib/main.dart', 'void main() {}');
  });
  tearDown(() => workspace.dispose());

  Future<List<String>> unused({bool strict = false}) async {
    final result = await KarekiRunner().analyze(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
        enabledRules: {RuleId.unusedPubDependency},
        strictDependencies: strict,
      ),
    );
    return result.findings.map((finding) => finding.stableId).toList();
  }

  test(
    'build and link hooks retain only their imported dependencies',
    () async {
      workspace.writePubspec(
        name: 'app',
        dependencies: {'collection', 'path', 'unused'},
      );
      workspace.write('hook/build.dart', '''
import 'package:collection/collection.dart';
void main() { print(const ListEquality<int>()); }
''');
      workspace.write('hook/link.dart', '''
import 'package:path/path.dart';
void main() { print(join('a', 'b')); }
''');
      expect(await unused(), ['pubdep|app|unused']);
    },
  );

  for (final registered in [false, true]) {
    test('nested example ownership (registered: $registered)', () async {
      workspace.write('pubspec.yaml', '''
name: app
environment:
  sdk: ^3.10.0
${registered ? 'workspace: [example]' : ''}
dependencies:
  collection: any
''');
      workspace.write('example/pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.10.0
${registered ? 'resolution: workspace' : ''}
dependencies:
  collection: any
''');
      workspace.write('example/lib/main.dart', '''
import 'package:collection/collection.dart';
void main() { print(const ListEquality<int>()); }
''');
      expect(await unused(), ['pubdep|app|collection']);
    });
  }

  test('documentation imports count in normal and strict modes', () async {
    workspace.writePubspec(
      name: 'app',
      dependencies: {'collection', 'unused'},
      devDependencies: {'path', 'unused_dev'},
    );
    workspace.write('lib/main.dart', '''
/// @docImport 'package:collection/collection.dart';
/// Documentation referencing [ListEquality].
void main() {}
class Example {
  /// @docImport 'package:path/path.dart' as paths;
  /// Documentation referencing [paths.join].
  void method() {}
}
''');
    expect(await unused(), ['pubdep|app|unused']);
    expect(await unused(strict: true), [
      'pubdep|app|unused',
      'pubdep|app|unused_dev',
    ]);
  });

  test(
    'doc imports stay separate from runtime imports and string contents',
    () {
      final parsed = DeclarationCollector().collect(
        path: '${workspace.path}/lib/example.dart',
        packageName: 'app',
        content: '''
/// @docImport 'package:collection/collection.dart';
class Example {}
const text = "/// @docImport 'package:fake/fake.dart';";
// @docImport 'package:another/another.dart';
''',
      );
      expect(parsed.docImports, ['package:collection/collection.dart']);
      expect(parsed.imports, isEmpty);
    },
  );

  test('explicit builders honor disabled settings and key aliases', () async {
    workspace.writePubspec(
      name: 'app',
      devDependencies: {'full', 'short', 'legacy', 'disabled', 'global_only'},
    );
    workspace.write('build.yaml', r'''
targets:
  $default:
    builders:
      full:builder: {enabled: true}
      short: {}
      legacy|builder: {}
      disabled:builder: {enabled: false}
global_options:
  global_only:builder: {options: {some_option: true}}
''');
    expect(await unused(strict: true), [
      'pubdep|app|disabled',
      'pubdep|app|global_only',
    ]);
  });

  test('conditional doc imports retain each platform URI', () {
    final parsed = DeclarationCollector().collect(
      path: '${workspace.path}/lib/example.dart',
      packageName: 'app',
      content: '''
/// @docImport 'package:default_api/api.dart' if (dart.library.io) 'package:native_api/api.dart';
class Example {}
''',
    );
    expect(parsed.docImports, [
      'package:default_api/api.dart',
      'package:native_api/api.dart',
    ]);
    expect(parsed.imports, isEmpty);
  });

  test('auto-applied builders honor each target and reread metadata', () async {
    workspace.writePubspec(
      name: 'app',
      devDependencies: {'automatic', 'disabled', 'manual', 'root', 'all'},
    );
    for (final name in ['automatic', 'disabled', 'manual', 'root', 'all']) {
      workspace.write('vendor/$name/pubspec.yaml', 'name: $name\n');
      final autoApply = name == 'manual'
          ? 'none'
          : name == 'root'
          ? 'root_package'
          : name == 'all'
          ? 'all_packages'
          : 'dependents';
      workspace.write('vendor/$name/build.yaml', '''
builders:
  builder:
    import: "package:$name/builder.dart"
    builder_factories: [builder]
    build_extensions: {".dart": [".out.dart"]}
    auto_apply: $autoApply
''');
    }
    workspace.write('build.yaml', r'''
targets:
  $default:
    builders:
      automatic:builder: {enabled: false}
      disabled:builder: {enabled: false}
  other:
    builders:
      disabled:builder: {enabled: false}
''');
    expect(await unused(strict: true), [
      'pubdep|app|disabled',
      'pubdep|app|manual',
    ]);
    workspace.write('vendor/automatic/build.yaml', 'builders: {}\n');
    expect(await unused(strict: true), [
      'pubdep|app|automatic',
      'pubdep|app|disabled',
      'pubdep|app|manual',
    ]);
  });

  test(
    'workspace builders resolve from the ancestor pub configuration',
    () async {
      workspace.write('pubspec.yaml', '''
name: root
environment:
  sdk: ^3.10.0
workspace: [packages/app, packages/other]
''');
      for (final name in ['app', 'other']) {
        workspace.write('packages/$name/pubspec.yaml', '''
name: $name
environment:
  sdk: ^3.10.0
resolution: workspace
dev_dependencies:
  automatic: any
''');
        workspace.write('packages/$name/lib/main.dart', 'void main() {}');
      }
      workspace.write('vendor/automatic/pubspec.yaml', 'name: automatic\n');
      workspace.write('vendor/automatic/build.yaml', '''
builders:
  builder:
    import: "package:automatic/builder.dart"
    builder_factories: [builder]
    build_extensions: {".dart": [".out.dart"]}
    auto_apply: dependents
''');
      workspace.write('packages/other/build.yaml', r'''
targets:
  $default:
    builders:
      automatic:builder: {enabled: false}
''');
      expect(await unused(strict: true), ['pubdep|other|automatic']);
    },
  );
}
