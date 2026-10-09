import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:kareki/kareki.dart';
import 'package:kareki/src/reachability/external_decoder_models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  late TestWorkspace dependencies;
  late List<Map<String, dynamic>> packages;

  void configure() {
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          ...packages,
          {
            'name': 'app',
            'rootUri': Uri.directory(workspace.path).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
      }),
    );
  }

  void copyDependency(String name, {String? change}) {
    final package = packages.singleWhere((entry) => entry['name'] == name);
    final root = Uri.parse(package['rootUri'] as String).toFilePath();
    final destination = p.join(dependencies.path, name);
    for (final file in Directory(
      p.join(root, 'lib'),
    ).listSync(recursive: true).whereType<File>()) {
      final relative = p.relative(file.path, from: root);
      dependencies.write(p.join(name, relative), file.readAsStringSync());
    }
    if (change != null) {
      final file = File(p.join(destination, 'lib', change));
      dependencies.write(
        p.join(name, 'lib', change),
        '${file.readAsStringSync()}\n// Changed source, unchanged package identity.\n',
      );
    }
    package['rootUri'] = Uri.directory(destination).toString();
    configure();
  }

  Future<RunResult> analyze(String body, {String extra = ''}) {
    workspace.write('lib/api.dart', '''
import 'dart:convert' as sdk;
import 'package:jsonc/jsonc.dart' as jsonc;
import 'package:yaml/yaml.dart';
class Candidate { int operator [](Object key) => indexHelper(); }
int indexHelper() => 1;
void consume(dynamic value) {}
dynamic saved;
$extra
Future<void> run() async { $body }
''');
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart'; Future<void> main() => run();",
    );
    return KarekiRunner().analyze(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
        enabledRules: {RuleId.unusedElement},
      ),
    );
  }

  void expectProtected(RunResult result) {
    expect(
      result.analysisWarnings,
      contains(contains('Unresolved reference "[]"')),
    );
    expect(
      result.findings.map((f) => f.message),
      isNot(contains(contains("'indexHelper'"))),
    );
  }

  void expectProven(RunResult result) {
    expect(result.analysisWarnings, isEmpty);
    expect(
      result.findings.map((f) => f.message),
      contains(contains("'indexHelper'")),
    );
  }

  setUp(() {
    workspace = TestWorkspace.create('kareki_decoder_app_');
    dependencies = TestWorkspace.create('kareki_decoder_deps_');
    workspace.writePubspec(name: 'app', dependencies: {'jsonc', 'yaml'});
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    packages = [
      for (final value in config['packages'] as List<dynamic>)
        if ((value as Map<String, dynamic>)['name'] != 'kareki')
          {
            ...value,
            'rootUri': configFile.uri
                .resolve(value['rootUri'] as String)
                .toString(),
          },
    ];
    configure();
  });

  tearDown(() {
    workspace.dispose();
    dependencies.dispose();
  });

  const yamlBody = '''
final root = loadYaml('name: sample');
final name = root['name'] as String?;
if (name != null) print(name);
final deps = root['dependencies'] as YamlMap?;
if (deps != null) print(deps.keys.where((key) => key.toString().isNotEmpty).toList());
''';
  const jsoncBody = '''
final root = jsonc.jsonc.decode('{}');
for (final device in root['devices'] as List<dynamic>) {
  final id = device['id'] as String;
  final version = device['version'] as String;
  await Future<void>.value();
  consume(id); consume(version);
}
''';

  test(
    'reviewed YAML source supports scalar reads and immutable keys',
    () async {
      expectProven(await analyze(yamlBody));
    },
  );
  test(
    'YAML cast and typed index proof needs no prior model activation',
    () async {
      expectProven(
        await analyze('''
final root = loadYaml('{}') as YamlMap;
final entries = root['entries'] as YamlList;
print(entries[0]['name'] as String);
'''),
      );
    },
  );
  test('reviewed JSONC source supports final List iteration', () async {
    expectProven(await analyze(jsoncBody));
    expectProven(await analyze("print(jsonc.jsoncDecode('{}')['x'] as int);"));
  });
  test('SDK JSON uses the same closed iteration proof', () async {
    expectProven(
      await analyze(
        jsoncBody.replaceFirst('jsonc.jsonc.decode', 'sdk.jsonDecode'),
      ),
    );
  });
  test(
    'proven loop reads do not hide unrelated same-name dynamic reads',
    () async {
      final result = await analyze('''
$jsoncBody
{ final dynamic device = Candidate(); print(device['id']); }
''');
      expectProtected(result);
      expect(
        'IndexExpressionImpl; context:'.allMatches(
          result.analysisWarnings.single,
        ),
        hasLength(1),
      );
    },
  );
  test('source contracts survive relocation but not source changes', () async {
    copyDependency('jsonc');
    expectProven(await analyze(jsoncBody));
    final file = File(p.join(dependencies.path, 'jsonc/lib/src/internal.dart'));
    dependencies.write(
      'jsonc/lib/src/internal.dart',
      '${file.readAsStringSync()}\n// changed\n',
    );
    expectProtected(await analyze(jsoncBody));
  });
  test(
    'YAML model rejects changed implementation or transitive source',
    () async {
      copyDependency('yaml', change: 'src/loader.dart');
      expectProtected(await analyze(yamlBody));
    },
  );
  test('YAML model rejects changed collection dependency', () async {
    copyDependency('collection', change: 'src/wrappers.dart');
    expectProtected(await analyze(yamlBody));
  });
  test('model rejects a changed effective language version', () async {
    packages.singleWhere(
      (entry) => entry['name'] == 'jsonc',
    )['languageVersion'] = '3.10';
    configure();
    expectProtected(await analyze(jsoncBody));
  });
  test('external model never hides a decoder owned by the workspace', () async {
    workspace.write('lib/api.dart', "import 'package:jsonc/jsonc.dart';");
    final source = p.join(workspace.path, 'lib/api.dart');
    final collection = AnalysisContextCollection(includedPaths: [source]);
    try {
      final result =
          await collection
                  .contextFor(source)
                  .currentSession
                  .getLibraryByUri('package:jsonc/src/json.dart')
              as LibraryElementResult;
      final decoder = result.element.classes
          .singleWhere((c) => c.name == 'JsoncCodec')
          .methods
          .singleWhere((m) => m.name == 'decode');
      expect(
        ExternalDecoderModels(isWorkspaceSource: (_) => true).kindOf(decoder),
        isNull,
      );
      expect(
        ExternalDecoderModels(isWorkspaceSource: (_) => false).kindOf(decoder),
        DecodedValueKind.json,
      );
    } finally {
      await collection.dispose();
    }
  });
  test('same-name fake decoder is not a trusted implementation', () async {
    dependencies.write('jsonc/lib/jsonc.dart', "export 'src/json.dart';");
    dependencies.write('jsonc/lib/src/json.dart', '''
class JsoncCodec { const JsoncCodec(); dynamic decode(String source) => null; }
const jsonc = JsoncCodec();
''');
    packages.singleWhere((entry) => entry['name'] == 'jsonc')['rootUri'] =
        Uri.directory(p.join(dependencies.path, 'jsonc')).toString();
    configure();
    expectProtected(await analyze(jsoncBody));
  });
  test('external models reject hooks, alias codecs and mutable bindings', () async {
    for (final body in [
      "final root = jsonc.jsoncDecode('{}', reviver: (k, v) => Candidate()); print(root['a'] as int);",
      "final root = jsonc.jsonc.decode('{}', reviver: null); print(root['a'] as int);",
      "final codec = jsonc.jsonc; final root = codec.decode('{}'); print(root['a'] as int);",
      "final root = jsonc.JsoncCodec(reviver: (k, v) => Candidate()).decode('{}'); print(root['a'] as int);",
      "final root = loadYaml('{}', recover: true); print(root['a'] as String);",
      "var root = loadYaml('{}'); print(root['a'] as String);",
      "final root = loadYaml('{}'); saved = root; print(root['a'] as String);",
      "final root = loadYaml('{}'); print(root['a'] as String); consume((root as YamlMap).nodes);",
    ]) {
      expectProtected(await analyze(body));
    }
  });
  test('iteration refuses mutation escape capture and non-List consumers', () async {
    for (final body in [
      "for (var device in root['devices'] as List) { print(device['id'] as String); }",
      "for (final device in root['devices'] as List) { consume(device); print(device['id'] as String); }",
      "for (final device in root['devices'] as List) { device['id'] = Candidate(); print(device['id']['x']); }",
      "for (final device in root['devices'] as List) { final read = () => device['id'] as String; consume(read); }",
      "for (final device in root['devices'] as Iterable) { print(device['id'] as String); }",
      "final values = [for (final device in root['devices'] as List) device]; consume(values);",
      "final devices = root['devices'] as List; devices.add(Candidate()); for (final device in devices) { print(device['id'] as String); }",
    ]) {
      expectProtected(
        await analyze("final root = jsonc.jsonc.decode('{}'); $body"),
      );
    }
  });
}
