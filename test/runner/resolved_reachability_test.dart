import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/cli/cli.dart';
import 'package:kareki/src/entry_points/entry_point_resolver.dart';
import 'package:kareki/src/reachability/resolved_reachability.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  void configurePackages([Map<String, String> packages = const {'app': '.'}]) {
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final entry in packages.entries)
            {
              'name': entry.key,
              'rootUri': Uri.directory(
                p.join(workspace.path, entry.value),
              ).toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.10',
            },
        ],
      }),
    );
  }

  RunRequest request({Set<String>? packages, Set<String>? rules}) => RunRequest(
    rootPath: workspace.path,
    config: KarekiConfig.load(workspace.path),
    includePackages: packages,
    enabledRules: rules ?? {RuleId.unusedElement, RuleId.testOnlyUsed},
  );

  Future<RunResult> analyze() => KarekiRunner().analyze(request());

  Iterable<String> unused(RunResult result) => result.findings
      .where((f) => f.ruleId == RuleId.unusedElement)
      .map((f) => f.message);

  setUp(() {
    workspace = TestWorkspace.create('kareki_resolved_runner_');
    workspace.writePubspec(name: 'app');
    configurePackages();
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart';\nvoid main() => A().save();\n",
    );
    workspace.write('lib/api.dart', '''
class A { void save() {} }
class B { void save() => deadHelper(); }
void deadHelper() {}
''');
  });
  tearDown(() => workspace.dispose());

  test(
    'null assertions retain exact fields and getters without homonym edges',
    () async {
      workspace.write('lib/api.dart', '''
int helper() => 1;
class Used {
  final int? entity = 1;
  int? get value => helper();
  int? operator [](int index) => helper();
}
class Unrelated { final int? entity = 1; int? get value => 2; }
''');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() {
  final used = Used();
  print(used.entity!);
  print(Used().value!);
  print(used[0]!);
  int? entity = 1;
  print(entity!);
  Used? maybe = DateTime.now().isUtc ? used : null;
  print(maybe?.value!);
}
''');
      final result = await analyze();
      expect(
        unused(result),
        unorderedEquals([
          contains("'Unrelated'"),
          contains("'Unrelated.entity'"),
          contains("'Unrelated.value'"),
        ]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'test null assertions and function calls cannot create test-only homonyms',
    () async {
      workspace.write('lib/api.dart', '''
class Unrelated { final int? entity = 1; void call() {} }
''');
      workspace.write('bin/main.dart', 'void main() {}');
      workspace.write('test/api_test.dart', '''
void main() {
  int? entity = 1;
  print(entity!);
  void Function()? callback = DateTime.now().isUtc ? () {} : null;
  callback?.call();
}
''');
      final result = await analyze();
      expect(result.findings, hasLength(3));
      expect(
        result.findings.every((f) => f.ruleId == RuleId.unusedElement),
        isTrue,
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'typed function call syntax retains receivers and arguments only',
    () async {
      workspace.write('lib/api.dart', '''
void target(Object value) { print(value); }
void Function(Object) makeCallback() => target;
Object payload() => 1;
T identity<T>(T value) => value;
class Unrelated { void call() {} }
class Callable { void call() => helper(); }
void helper() {}
''');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() {
  final callback = makeCallback();
  callback.call(payload());
  (callback).call(payload());
  callback..call(payload());
  final tearOff = callback.call;
  tearOff(payload());
  final generic = identity;
  print(generic.call<int>(1));
  Callable().call();
}
''');
      final result = await analyze();
      expect(
        unused(result),
        unorderedEquals([
          contains("'Unrelated'"),
          contains("'Unrelated.call'"),
        ]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test('nested example sources have one record set owned by the child', () async {
    workspace.write(
      'pubspec.yaml',
      "name: app\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\nworkspace: [example]\n",
    );
    workspace.write('example/pubspec.yaml', 'name: sample\n');
    configurePackages({'app': '.', 'sample': 'example'});
    workspace.write('example/lib/main.dart', '''
void main() { App().run(); }
class App { App(); void run() {} }
''');
    workspace.write('example/lib/dead.dart', 'void unusedExample() {}');
    final result = await analyze();
    final exampleFindings = result.findings.where(
      (f) => f.filePath.contains('/example/'),
    );
    expect(exampleFindings, hasLength(1));
    expect(exampleFindings.single.message, contains("'unusedExample'"));
    expect(exampleFindings.single.packageName, 'sample');
    expect(result.filesAnalyzed, 4);
    expect(result.analysisWarnings, isEmpty);

    final parentOnly = await KarekiRunner().analyze(request(packages: {'app'}));
    expect(parentOnly.filesAnalyzed, 2);
    expect(parentOnly.findings.every((f) => f.packageName == 'app'), isTrue);
    final childOnly = await KarekiRunner().analyze(
      request(packages: {'sample'}),
    );
    expect(childOnly.filesAnalyzed, 2);
    expect(childOnly.findings.single.stableId, exampleFindings.single.stableId);

    // Analyzer returns canonical paths even when the checkout is opened via
    // a symlink. Reporting and the graph must still share the same records.
    final aliasWorkspace = TestWorkspace.create('kareki_resolved_alias_');
    try {
      final alias = p.join(aliasWorkspace.path, 'checkout');
      Link(alias).createSync(workspace.path);
      final viaAlias = await KarekiRunner().analyze(
        RunRequest(
          rootPath: alias,
          config: KarekiConfig.load(alias),
          enabledRules: {RuleId.unusedElement, RuleId.testOnlyUsed},
        ),
      );
      expect(viaAlias.filesAnalyzed, 4);
      expect(
        viaAlias.findings.map((f) => '${f.packageName}:${f.message}'),
        unorderedEquals(
          result.findings.map((f) => '${f.packageName}:${f.message}'),
        ),
      );
      expect(viaAlias.analysisWarnings, isEmpty);
    } finally {
      aliasWorkspace.dispose();
    }

    workspace.write('kareki.yaml', 'ignore:\n  packages: [sample]\n');
    final ignoredChild = await analyze();
    expect(ignoredChild.filesAnalyzed, 2);
    expect(ignoredChild.findings.every((f) => f.packageName == 'app'), isTrue);
    expect(ignoredChild.analysisWarnings, isEmpty);
  });

  test(
    'an example without a workspace package stays owned by its parent',
    () async {
      workspace.write('example/lib/main.dart', '''
void main() { Example().run(); }
class Example { void run() {} }
''');
      workspace.write('example/lib/dead.dart', 'void unusedExample() {}');
      final result = await analyze();
      final exampleFindings = result.findings.where(
        (f) => f.filePath.contains('/example/'),
      );
      expect(exampleFindings, hasLength(1));
      expect(exampleFindings.single.message, contains("'unusedExample'"));
      expect(exampleFindings.single.packageName, 'app');
      expect(result.filesAnalyzed, 4);
    },
  );

  test(
    'record fields do not retain unrelated same-named declarations',
    () async {
      workspace.write('bin/main.dart', 'void main() {}\n');
      workspace.write('lib/api.dart', r'''
class Unused {
  final int flag = 1;
  final int $1 = 2;
  void action() {}
}
''');
      workspace.write('test/api_test.dart', r'''
void main() {
  final row = (1, flag: 2, action: (Object value) => print(value));
  print(row.flag);
  print(row.$1);
  print((row).flag);
  print((row).$1);
  row.action(row.flag);
  (row).action(row.$1);
  row..action(row.flag);
  (int, {int flag})? nullable = DateTime.now().isUtc ? null : (1, flag: 2);
  print(nullable?.flag);
  print(nullable?.$1);
}
''');
      final result = await analyze();
      // The existing reporting policy excludes dollar-prefixed names; the $1
      // access is still checked for spurious fallback via analysisWarnings.
      expect(result.findings, hasLength(3));
      expect(
        unused(result),
        containsAll([
          contains("'Unused'"),
          contains("'Unused.flag'"),
          contains("'Unused.action'"),
        ]),
      );
      expect(
        result.findings.every((f) => f.ruleId == RuleId.unusedElement),
        isTrue,
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'record receivers, callable arguments and extension members stay live',
    () async {
      workspace.write('lib/api.dart', '''
Object payload() => 1;
({int flag, void Function(Object) action}) makeRow() => (flag: 1, action: consume);
void consume(Object value) { print(value); }
extension RecordTools on ({int flag, void Function(Object) action}) {
  int get doubled => flag * 2;
  void show() { print(doubled); }
}
''');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() {
  final row = makeRow();
  row.action(payload());
  makeRow().action(payload());
  print(row.doubled);
  row.show();
  print(row.toString());
}
''');
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'analyzer-excluded generated libraries and parts still retain references',
    () async {
      workspace.write(
        'analysis_options.yaml',
        "analyzer:\n  exclude: ['**/*.g.dart']\n",
      );
      workspace.write(
        'lib/api.dart',
        "part 'api.g.dart';\nclass A { void save() {} }\nclass B { void save() {} }\n",
      );
      workspace.write(
        'lib/api.g.dart',
        "part of 'api.dart';\nvoid generatedPart() => B().save();\n",
      );
      workspace.write(
        'lib/client.g.dart',
        "import 'api.dart';\nvoid generatedLibrary() => A().save();\n",
      );
      workspace.write('bin/main.dart', 'void main() {}\n');
      final result = await analyze();
      expect(unused(result), isEmpty);
      expect(result.analysisWarnings, isEmpty);
      expect(
        await runCli([
          '--root',
          workspace.path,
          '--rule',
          'unused_element',
        ], workingDirectory: workspace.path),
        0,
      );
      workspace.write(
        'lib/client.g.dart',
        'void generatedLibrary() => missing();\n',
      );
      workspace.write('baseline.json', 'keep existing baseline');
      expect(
        await runCli([
          '--root',
          workspace.path,
          '--baseline',
          'baseline.json',
          '--write-baseline',
        ], workingDirectory: workspace.path),
        2,
      );
      expect(
        File(p.join(workspace.path, 'baseline.json')).readAsStringSync(),
        'keep existing baseline',
      );
    },
  );

  test(
    'excluded sources select their nested package config and options',
    () async {
      workspace.write(
        'analysis_options.yaml',
        "analyzer:\n  exclude: ['**/*.g.dart']\n",
      );
      workspace.write(
        'pubspec.yaml',
        "name: app\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\nworkspace: [packages/child]\n",
      );
      workspace.write(
        'packages/child/pubspec.yaml',
        "name: child\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n",
      );
      workspace.write(
        'packages/child/analysis_options.yaml',
        "analyzer:\n  exclude: ['**/*.g.dart']\n",
      );
      workspace.write(
        'packages/child/.dart_tool/package_config.json',
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'child',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.10',
            },
          ],
        }),
      );
      workspace.write('packages/child/lib/api.dart', 'void nestedOnly() {}\n');
      workspace.write(
        'packages/child/lib/client.g.dart',
        "import 'package:child/api.dart';\nvoid generated() => nestedOnly();\n",
      );
      final result = await analyze();
      expect(unused(result), isNot(contains(contains("'nestedOnly'"))));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test('analyzer context failures become incomplete-analysis errors', () async {
    final outside = TestWorkspace.create('kareki_outside_context_');
    try {
      outside.write('outside.dart', 'void outside() {}');
      final path = p.join(outside.path, 'outside.dart');
      final file = DeclarationCollector().collect(
        path: path,
        packageName: 'app',
        content: 'void outside() {}',
      );
      await expectLater(
        ResolvedReachability.build(
          files: [file],
          generatedPaths: {},
          entryPoints: EntryPointSet(
            entryPointPaths: {},
            keepAliveAnnotations: {},
          ),
          config: KarekiConfig.defaults(),
          packageRoots: {'app': workspace.path},
        ),
        throwsA(
          isA<ResolvedAnalysisException>().having(
            (e) => e.diagnostics.join(),
            'diagnostics',
            contains('No owning analysis context'),
          ),
        ),
      );
    } finally {
      outside.dispose();
    }
  });

  test(
    'dot shorthand constructors and extension types retain called bodies',
    () async {
      workspace.write('lib/api.dart', '''
class A { A.named() { namedHelper(); } A() { unnamedHelper(); } }
A named() => .named();
A unnamed() => .new();
void namedHelper() {}
void unnamedHelper() {}
extension type UserId(int value) { String format() => formatHelper(value); }
String formatHelper(int value) => value.toString();
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() { named(); unnamed(); UserId(1).format(); }\n",
      );
      expect(unused(await analyze()), isEmpty);
    },
  );

  test(
    'primary declaring fields and their accessors share exact identities',
    () async {
      workspace.write(
        'analysis_options.yaml',
        'analyzer:\n  enable-experiment:\n    - primary-constructors\n',
      );
      workspace.write('lib/api.dart', '''
class A.named(final int value) { int read() => value; }
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() { print(A.named(1).read()); }\n",
      );
      final result = await analyze();
      expect(unused(result), isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'constructors, inherited setters and field formals retain dependencies',
    () async {
      workspace.write('lib/api.dart', '''
abstract class Contract { set value(int value); }
class Base { Base.named() { initialize(); } }
class A extends Base implements Contract {
  A(this.field) : super.named();
  A.redirect() : this(1);
  final int field;
  set value(int value) { setterHelper(); }
}
void initialize() {}
void setterHelper() {}
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() { Contract a = A.redirect(); a.value = 2; }\n",
      );
      expect(unused(await analyze()), isEmpty);
    },
  );

  test(
    'operator reads and writes, object patterns and enum constructors resolve',
    () async {
      workspace.write('lib/api.dart', '''
class A {
  A operator +(Object other) { plusHelper(); return this; }
  A operator -() { minusHelper(); return this; }
  int operator [](int index) => readHelper();
  void operator []=(int index, int value) { writeHelper(); }
  int get value => patternHelper();
  set value(int value) { setterHelper(); }
}
void plusHelper() {}
void minusHelper() {}
int readHelper() => 1;
void writeHelper() {}
int patternHelper() => 1;
void setterHelper() {}
enum Choice { first.named(); const Choice.named(); }
/// Documentation alone must not keep [dead] alive.
void documented() {}
void dead() {}
''');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() {
  var a = A();
  a + a; -a; a += a; a++; ++a;
  a[0]; a[0] = 1; a[0] += 1;
  ++a.value; (a).value = 2;
  if (a case A(value: final value)) { print(value); }
  print(Choice.first); documented();
}
''');
      final result = await analyze();
      expect(unused(result).toList(), [contains("'dead'")]);
    },
  );

  test('conditional package exports preserve every platform', () async {
    workspace.write(
      'lib/api.dart',
      "export 'package:app/stub.dart' if (dart.library.html) 'package:app/browser.dart';\n",
    );
    workspace.write('lib/stub.dart', 'void platform() {}\n');
    workspace.write('lib/browser.dart', 'void platform() {}\n');
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart';\nvoid main() => platform();\n",
    );
    final result = await analyze();
    expect(unused(result), isEmpty);
    expect(result.analysisWarnings, isEmpty);
  });

  test(
    'conditional facades retain every branch body, not unused siblings',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.target == 'browser') 'browser.dart';",
      );
      // Same public namespace; body-only dependencies can differ by branch.
      workspace.write(
        'lib/stub.dart',
        "import 'helpers.dart'; void platform() => _stubHelper(); void _stubHelper() => stubUsed(); void extra() {}",
      );
      workspace.write(
        'lib/browser.dart',
        "import 'helpers.dart'; void platform() => _browserHelper(); void _browserHelper() => browserUsed(); void extra() {}",
      );
      workspace.write(
        'lib/helpers.dart',
        'void stubUsed() {} void browserUsed() {} void unrelated() {}',
      );
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => platform();",
      );
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result).where((m) => m.contains("'extra'")), hasLength(2));
      expect(
        unused(result).where((m) => m.contains("'unrelated'")),
        hasLength(1),
      );
      expect(unused(result).any((m) => m.contains('Used')), isFalse);
    },
  );

  test(
    'conditional getters retain alternate bodies with identical core types',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (dart.library.io) 'other.dart';",
      );
      workspace.write(
        'lib/stub.dart',
        "import 'helpers.dart'; bool get enabled => stubUsed();",
      );
      workspace.write(
        'lib/other.dart',
        "import 'helpers.dart'; bool get enabled => otherUsed();",
      );
      workspace.write(
        'lib/helpers.dart',
        'bool stubUsed() => true; bool otherUsed() => false;',
      );
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() { print(enabled); }",
      );
      final result = await analyze();
      expect(unused(result), isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'unreachable compatible facades are not unconditional production roots',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write('lib/stub.dart', 'void unusedFacade() {}');
      workspace.write('lib/other.dart', 'void unusedFacade() {}');
      workspace.write('bin/main.dart', 'void main() {}');
      final result = await analyze();
      expect(unused(result), hasLength(2));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'conditional facade homonyms outside a directive are not joined',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write('lib/stub.dart', 'void platform() {}');
      workspace.write('lib/other.dart', 'void platform() {}');
      workspace.write('lib/unrelated.dart', 'void platform() {}');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => platform();",
      );
      final result = await analyze();
      expect(unused(result), hasLength(1));
      expect(result.findings.single.filePath, endsWith('unrelated.dart'));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  for (final alternate in <String>[
    'int platform() => 1;',
    'void get platform {}',
    'dynamic platform() => null;',
    'Never platform() => throw 0;',
    'List<int> platform() => [];',
    'void platform() => _helper(); void _helper({int? value}) {}',
    'void platform({int? value}) {}',
    'void platform<T>() {}',
    'platform() {}',
    'void platform() {} class Extra {}',
    'void platform() {} final extra = 1;',
    "export 'shared.dart'; void platform() {}",
    "part 'piece.dart'; void platform() {}",
    "import 'shared.dart' if (custom.nested) 'shared.dart'; void platform() {}",
  ]) {
    test(
      'unsupported conditional namespace retains warning: $alternate',
      () async {
        workspace.write(
          'lib/api.dart',
          "export 'stub.dart' if (custom.flavor) 'other.dart';",
        );
        workspace.write('lib/stub.dart', 'void platform() {}');
        workspace.write('lib/other.dart', alternate);
        workspace.write('lib/shared.dart', 'void helper() {}');
        workspace.write('lib/piece.dart', "part of 'other.dart';");
        workspace.write(
          'bin/main.dart',
          "import 'package:app/api.dart'; void main() => platform();",
        );
        final result = await analyze();
        final warning = result.analysisWarnings.firstWhere(
          (w) => w.contains('Conditional'),
        );
        expect(warning, contains('lib/api.dart:1:1'));
        expect(warning, contains('custom.flavor == true'));
        expect(warning, contains('default -> stub.dart'));
        expect(warning, contains('Workspace targets:'));
        expect(unused(result).any((m) => m.contains("'platform'")), isFalse);
      },
    );
  }

  test(
    'conditional facades compare external return types by declaration identity',
    () async {
      configurePackages({'app': '.', 'dependency': '.dependency'});
      workspace.write(
        '.dependency/lib/shared.dart',
        'class Adapter { void send() {} }',
      );
      workspace.write(
        '.dependency/lib/different.dart',
        'class Adapter { void send() {} }',
      );
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write(
        'lib/stub.dart',
        "import 'package:dependency/shared.dart'; Adapter create() => Adapter();",
      );
      workspace.write(
        'lib/other.dart',
        "import 'package:dependency/shared.dart'; Adapter create() => Adapter();",
      );
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => create().send();",
      );
      final compatible = await analyze();
      expect(unused(compatible), isEmpty);
      expect(compatible.analysisWarnings, isEmpty);
      // The display name stays 'Adapter', but the defining library changes.
      workspace.write(
        'lib/other.dart',
        "import 'package:dependency/different.dart'; Adapter create() => Adapter();",
      );
      final incompatible = await analyze();
      expect(unused(incompatible), isEmpty);
      expect(incompatible.analysisWarnings, contains(contains('Conditional')));
      workspace.write(
        'lib/other.dart',
        "import 'package:dependency/shared.dart'; Adapter? create() => null;",
      );
      expect(
        (await analyze()).analysisWarnings,
        contains(contains('Conditional')),
      );
    },
  );

  test(
    'shared targets keep protection when any directive is unsupported',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write(
        'lib/unsupported.dart',
        "export 'stub.dart' if (custom.flavor) 'missing.dart';",
      );
      workspace.write('lib/stub.dart', 'void platform() {}');
      workspace.write('lib/other.dart', 'void platform() {}');
      workspace.write('bin/main.dart', 'void main() {}');
      final result = await analyze();
      expect(unused(result), isEmpty);
      final warning = result.analysisWarnings.single;
      expect(warning, contains('Conditional'));
      expect(warning, contains('lib/unsupported.dart'));
      expect(warning, isNot(contains('lib/api.dart:')));
    },
  );

  test(
    'prefixes and combinators retain all alternative bodies without matching unrelated imports',
    () async {
      workspace.write(
        'lib/api.dart',
        "import 'stub.dart' if (custom.flavor) 'other.dart' as selected show platform; void run() => selected.platform();",
      );
      workspace.write('lib/stub.dart', 'void platform() {} void hidden() {}');
      workspace.write('lib/other.dart', 'void platform() {} void hidden() {}');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => run();",
      );
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), hasLength(2));
      expect(unused(result).every((m) => m.contains("'hidden'")), isTrue);
    },
  );

  test(
    'all conditional branches are joined including duplicate conditions and third alternatives',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'one.dart' if (custom.flavor == 'yes') 'two.dart' if (custom.flavor == 'yes') 'three.dart';",
      );
      for (final name in ['one', 'two', 'three']) {
        workspace.write('lib/$name.dart', 'void platform() {}');
      }
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => platform();",
      );
      final result = await analyze();
      expect(unused(result), isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'test-only references keep conditional alternatives test-only',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write('lib/stub.dart', 'void platform() {}');
      workspace.write('lib/other.dart', 'void platform() {}');
      workspace.write('bin/main.dart', 'void main() {}');
      workspace.write(
        'test/usage_test.dart',
        "import 'package:app/api.dart'; void main() => platform();",
      );
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(
        result.findings.where((f) => f.ruleId == RuleId.testOnlyUsed),
        hasLength(2),
      );
      expect(unused(result), isEmpty);
    },
  );

  test(
    'mixed test and production conditional targets keep production protection',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'test/stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write('lib/test/stub.dart', 'void platform() {}');
      workspace.write('lib/other.dart', 'void platform() {}');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => platform();",
      );
      final result = await analyze();
      expect(result.analysisWarnings, contains(contains('Conditional')));
      expect(
        result.findings.where((f) => f.filePath.endsWith('other.dart')),
        isEmpty,
      );
    },
  );

  test(
    'an invalid unselected branch aborts rather than claiming full coverage',
    () async {
      workspace.write(
        'lib/api.dart',
        "export 'stub.dart' if (custom.flavor) 'other.dart';",
      );
      workspace.write('lib/stub.dart', 'void platform() {}');
      workspace.write('lib/other.dart', 'void platform() => missing();');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => platform();",
      );
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
    },
  );

  test(
    'a stale parsed snapshot is retained with a warning, not reported dead',
    () async {
      final path = p.join(workspace.path, 'lib/api.dart');
      final file = DeclarationCollector().collect(
        path: path,
        packageName: 'app',
        content: 'void previous() {}',
      );
      workspace.write('lib/api.dart', 'void replacement() {}');
      final result = await ResolvedReachability.build(
        files: [file],
        generatedPaths: {},
        entryPoints: EntryPointSet(
          entryPointPaths: {},
          keepAliveAnnotations: {},
        ),
        config: KarekiConfig.defaults(),
        packageRoots: {'app': workspace.path},
      );
      expect(result.reachable, contains(file.declarations.single));
      expect(result.warnings, contains(contains('Could not map')));
      File(path).deleteSync();
      await expectLater(
        ResolvedReachability.build(
          files: [file],
          generatedPaths: {},
          entryPoints: EntryPointSet(
            entryPointPaths: {},
            keepAliveAnnotations: {},
          ),
          config: KarekiConfig.defaults(),
          packageRoots: {'app': workspace.path},
        ),
        throwsA(isA<ResolvedAnalysisException>()),
      );
    },
  );

  test('unreadable source fails without a partial analysis', () async {
    File(p.join(workspace.path, 'lib/api.dart')).writeAsBytesSync([0xff]);
    await expectLater(analyze, throwsA(isA<ResolvedAnalysisException>()));
  });

  test('CLI warnings and removed mode options are explicit', () async {
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart';\nvoid main() { dynamic a = A(); a.save(); }\n",
    );
    expect(
      await runCli([
        '--root',
        workspace.path,
        '--rule',
        'unused_element',
      ], workingDirectory: workspace.path),
      0,
    );
    expect(
      await runCli([
        '--root',
        workspace.path,
        '--analysis-mode',
        'resolved',
      ], workingDirectory: workspace.path),
      64,
    );
    workspace.write('kareki-config.yaml', '');

    workspace.write('kareki-config.yaml', 'analysis_mode: invalid\n');
    expect(
      await runCli([
        'doctor',
        '--root',
        workspace.path,
      ], workingDirectory: workspace.path),
      64,
    );
  });

  test(
    'same-file homonyms separate, including bodies of dead members',
    () async {
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() { A().save(); B(); }\n",
      );
      final result = await analyze();
      expect(
        unused(result),
        containsAll([contains("'B.save'"), contains("'deadHelper'")]),
      );
      expect(unused(result), isNot(contains(contains("'A.save'"))));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'top-level homonyms and local shadows cannot rescue unrelated APIs',
    () async {
      workspace.write('lib/api.dart', 'void save() {}\n');
      workspace.write('lib/other.dart', 'void save() {}\n');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart' as used;
void main() { used.save(); local(); }
void local() { void save() {} save(); }
''');
      final result = await analyze();
      expect(
        result.findings
            .where((f) => f.ruleId == RuleId.unusedElement)
            .single
            .filePath,
        endsWith('other.dart'),
      );
    },
  );

  test('production and test roots do not merge same-name members', () async {
    workspace.write(
      'test/api_test.dart',
      "import 'package:app/api.dart';\nvoid main() => B().save();\n",
    );
    final result = await analyze();
    final testOnly = result.findings
        .where((f) => f.ruleId == RuleId.testOnlyUsed)
        .map((f) => f.message);
    expect(
      testOnly,
      containsAll([contains("'B.save'"), contains("'deadHelper'")]),
    );
    expect(testOnly, isNot(contains(contains("'A.save'"))));
    expect(unused(result), isEmpty);
  });

  test('generated references keep only their resolved targets alive', () async {
    workspace.write('bin/main.dart', 'void main() {}\n');
    workspace.write(
      'lib/client.g.dart',
      "import 'api.dart';\nvoid generated() => A().save();\n",
    );
    final result = await analyze();
    expect(unused(result), contains(contains("'B.save'")));
    expect(unused(result), isNot(contains(contains("'A.save'"))));
  });

  test(
    'interface dispatch without annotations keeps implementations and bodies',
    () async {
      workspace.write('lib/api.dart', '''
abstract class Contract { void save(); }
class A implements Contract { void save() => usedHelper(); }
class B { void save() => deadHelper(); }
void usedHelper() {}
void deadHelper() {}
''');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() { Contract object = A(); object.save(); B(); }
''');
      final result = await analyze();
      expect(
        unused(result),
        containsAll([contains("'B.save'"), contains("'deadHelper'")]),
      );
      expect(unused(result), isNot(contains(contains("'A.save'"))));
      expect(unused(result), isNot(contains(contains("'usedHelper'"))));
    },
  );

  test(
    'mixin-provided implementations and implicit super constructors survive',
    () async {
      workspace.write('lib/api.dart', '''
abstract class Contract { void save(); }
mixin Implementation { void save() => helper(); }
class Base { Base() { initialize(); } }
class A extends Base with Implementation implements Contract {}
void helper() {}
void initialize() {}
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() { Contract object = A(); object.save(); }\n",
      );
      final result = await analyze();
      expect(unused(result), isEmpty);
    },
  );

  test(
    'field initialization and local closures retain their dependencies',
    () async {
      workspace.write('lib/api.dart', '''
class A {
  final value = initialize();
  void save() { final callback = () => helper(); callback(); }
}
int initialize() => 1;
void helper() {}
''');
      final result = await analyze();
      expect(unused(result), isNot(contains(contains("'initialize'"))));
      expect(unused(result), isNot(contains(contains("'helper'"))));
    },
  );

  test(
    'explicit accessors, compound assignments and generic methods resolve',
    () async {
      workspace.write('lib/api.dart', '''
class A<T> {
  int get value => getterHelper();
  set value(int input) { setterHelper(); }
  T save(T input) => input;
}
int getterHelper() => 1;
void setterHelper() {}
class B { int get value => 2; void save() {} }
''');
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() { final a = A<int>(); a.value++; a.save(1); A<String>().save('x'); B(); }
''');
      final result = await analyze();
      expect(
        unused(result),
        containsAll([contains("'B.value'"), contains("'B.save'")]),
      );
      expect(unused(result).length, 2);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'named constructors do not share reachability with their host',
    () async {
      workspace.write('lib/api.dart', '''
class A { A(); A.unused() { deadHelper(); } void save() {} }
void deadHelper() {}
''');
      final result = await analyze();
      expect(
        unused(result),
        containsAll([contains("'A.unused'"), contains("'deadHelper'")]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test('unreachable reference cycles stay unreachable', () async {
    workspace.write(
      'lib/api.dart',
      'class A { void save() {} }\nvoid first() => second();\nvoid second() => first();\n',
    );
    final result = await analyze();
    expect(
      unused(result),
      containsAll([contains("'first'"), contains("'second'")]),
    );
  });

  test(
    'dynamic references preserve candidates and disclose approximation',
    () async {
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() { dynamic object = A(); object.save(); }\n",
      );
      final result = await analyze();
      expect(unused(result), isEmpty);
      expect(
        result.analysisWarnings,
        contains(contains('Unresolved reference "save"')),
      );
    },
  );

  test(
    'dynamic evidence groups sites but does not assert candidate dispatch',
    () async {
      workspace.write('lib/api.dart', '''
class A { int operator [](int index) => index; }
void read(dynamic input) {
  print(input['secret-literal-not-for-logs']);
  print(input['another']);
  print(input['a']['b']['c']);
}
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() => read({'a': 1});",
      );
      final result = await analyze();
      final warning = result.analysisWarnings.single;
      expect(warning, contains('Unresolved reference "[]"'));
      expect(warning, contains('lib/api.dart:3:9'));
      expect(warning, contains('lib/api.dart:4:9'));
      expect(warning, contains('receiver type: dynamic'));
      expect('IndexExpressionImpl; context:'.allMatches(warning), hasLength(5));
      expect(warning, contains('Candidate declarations (not proven targets):'));
      expect(warning, contains('lib/api.dart:1 []'));
      expect(warning, isNot(contains('secret-literal-not-for-logs')));
      expect((await analyze()).analysisWarnings, result.analysisWarnings);
    },
  );

  test(
    'SDK JSON closed reads do not retain same-name index operators',
    () async {
      workspace.write('lib/api.dart', '''
class Candidate { int operator [](Object key) => indexHelper(); }
int indexHelper() => 1;
''');
      workspace.write('bin/main.dart', '''
import 'dart:convert' as convert;
void main() {
  final root = convert.json.decode('{}');
  final alias = (root);
  final child = alias['a'];
  print(child['b']['c'] as String?);
  print((root['groups']['flags']['parameters'] as Map).keys);
  print(((convert.jsonDecode('{}'))!['a'] as List)[0] as int);
  print((convert.jsonDecode('{}') as Map)['a']['b'] as String);
  print((convert.json).decode('{}')['a'] as bool);
}
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), contains(contains("'indexHelper'")));
    },
  );

  test(
    'SDK JSON proof keeps real source and index argument references',
    () async {
      workspace.write('lib/api.dart', '''
String source() => '{}';
String key() => 'key';
class Candidate { int operator [](Object key) => indexHelper(); }
int indexHelper() => 1;
''');
      workspace.write('bin/main.dart', '''
import 'dart:convert';
import 'package:app/api.dart';
void main() { print(jsonDecode(source())[key()] as String); }
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), contains(contains("'indexHelper'")));
      expect(unused(result), isNot(contains(contains("'source'"))));
      expect(unused(result), isNot(contains(contains("'key'"))));
    },
  );

  test('JSON provenance rejects escape and mutation on any alias', () async {
    const cases = [
      "var root = jsonDecode('{}'); print(root['a'] as String);",
      "var root = jsonDecode('{}'); root = Candidate(); print(root['a']);",
      "final root = jsonDecode('{}'); consume(root); print(root['a'] as String);",
      "final root = jsonDecode('{}'); print(root['a'] as String); consume(root);",
      "final root = jsonDecode('{}'); final alias = root; consume(alias); print(root['a'] as String);",
      "final root = jsonDecode('{}'); final child = root['a']; child['b'] = Candidate(); print(root['a']['b']);",
      "final root = jsonDecode('{}'); root['a'] = Candidate(); print(root['a']['b']);",
      "final root = jsonDecode('{}'); root['a'] += 1; print(root['a'] as int);",
      "final root = jsonDecode('{}'); ++root['a']; print(root['a'] as int);",
      "final root = jsonDecode('{}'); root['a']++; print(root['a'] as int);",
      "final root = jsonDecode('{}'); final read = () => root['a'] as String; print(read());",
      "final root = jsonDecode('{}'); print(root['a'] as String); consume((root as Map).values);",
      "final root = jsonDecode('{}'); print(root['a'] as String); (root as Map).clear();",
      "final root = jsonDecode('{}'); consume(root['a']); print(root['b'] as String);",
      "final root = jsonDecode('{}'); saved = root; print(root['a'] as String);",
      "final root = jsonDecode('{}'); print(root['a'] as String); print((root as Candidate)[0]);",
      "final root = jsonDecode('{}'); print([root]); print(root['a'] as String);",
      "final root = jsonDecode('{}'); print(root['a'] as String); return root;",
      "final root = jsonDecode('{}'); root..['a'] = Candidate(); print(root['a'] as String);",
    ];
    for (final body in cases) {
      workspace.write('lib/api.dart', '''
import 'dart:convert';
dynamic saved;
void consume(dynamic value) {}
class Candidate { int operator [](Object key) => indexHelper(); }
int indexHelper() => 1;
dynamic run() { $body }
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() { run(); }",
      );
      final result = await analyze();
      expect(
        result.analysisWarnings,
        contains(contains('Unresolved reference "[]"')),
        reason: body,
      );
      expect(
        unused(result),
        isNot(contains(contains("'indexHelper'"))),
        reason: body,
      );
    }
  });

  test(
    'JSON provenance verifies declaration and the exact codec receiver',
    () async {
      const cases = [
        "sdk.jsonDecode('{}', reviver: (k, v) => Candidate())",
        "sdk.json.decode('{}', reviver: (k, v) => Candidate())",
        "sdk.jsonDecode('{}', reviver: null)",
        "sdk.JsonCodec(reviver: (k, v) => Candidate()).decode('{}')",
        "codec.decode('{}')",
        "decoder('{}')",
        "jsonDecode('{}')",
        "json.decode('{}')",
      ];
      for (final expression in cases) {
        workspace.write('lib/api.dart', '''
import 'dart:convert' as sdk;
class Candidate { int operator [](Object key) => indexHelper(); }
int indexHelper() => 1;
dynamic jsonDecode(String value) => Candidate();
class FakeCodec { dynamic decode(String value) => Candidate(); }
final json = FakeCodec();
void run() {
  final codec = sdk.JsonCodec(reviver: (k, v) => Candidate());
  final decoder = sdk.jsonDecode;
  final root = $expression;
  print(root['a'] as int);
}
''');
        workspace.write(
          'bin/main.dart',
          "import 'package:app/api.dart'; void main() { run(); }",
        );
        final result = await analyze();
        expect(
          result.analysisWarnings,
          contains(contains('Unresolved reference "[]"')),
          reason: expression,
        );
        expect(
          unused(result),
          isNot(contains(contains("'indexHelper'"))),
          reason: expression,
        );
      }
    },
  );

  test(
    'explicit name roots preserve matching declarations intentionally',
    () async {
      workspace.write('kareki-config.yaml', 'entry_points:\n  names: [save]\n');
      final result = await analyze();
      expect(unused(result), isEmpty);
    },
  );

  test(
    'initializer and host fallback share one diagnostic source site',
    () async {
      workspace.write('lib/api.dart', '''
dynamic input = {'x': 1};
class A { final value = input['x']; }
class Candidate { int operator [](String key) => 1; }
''');
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() { A(); }",
      );
      final result = await analyze();
      final warning = result.analysisWarnings.single;
      expect(warning, contains('Unresolved reference "[]"'));
      expect('IndexExpressionImpl; context:'.allMatches(warning), hasLength(1));
      expect(unused(result), isNot(contains(contains("'Candidate.[]'"))));
    },
  );

  test('keep-alive annotations root only the annotated declaration', () async {
    workspace.write(
      'kareki-config.yaml',
      'keep_alive_annotations:\n  custom: [Keep]\n',
    );
    workspace.write('lib/api.dart', '''
class Keep { const Keep(); }
class A { @Keep() void save() {} }
class B { void save() {} }
''');
    workspace.write('bin/main.dart', 'void main() {}\n');
    final result = await analyze();
    expect(unused(result), contains(contains("'B.save'")));
    expect(unused(result), isNot(contains(contains("'A.save'"))));
  });

  test(
    'part and extension members are reachable through their own IDs',
    () async {
      workspace.write(
        'lib/api.dart',
        "part 'part.dart';\nextension Ext on String { void save() => helper(); }\n",
      );
      workspace.write(
        'lib/part.dart',
        "part of 'api.dart';\nvoid helper() {}\n",
      );
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart';\nvoid main() => 'x'.save();\n",
      );
      expect(unused(await analyze()), isEmpty);
    },
  );

  test('conditional alternatives are protected across platforms', () async {
    workspace.write(
      'lib/api.dart',
      "import 'stub.dart' if (dart.library.html) 'browser.dart';\nclass A { void save() => platform(); }\n",
    );
    workspace.write(
      'lib/stub.dart',
      'void platform() => stubHelper();\nvoid stubHelper() {}\n',
    );
    workspace.write(
      'lib/browser.dart',
      'void platform() => browserHelper();\nvoid browserHelper() {}\n',
    );
    final result = await analyze();
    expect(unused(result), isEmpty);
    expect(result.analysisWarnings, contains(contains('Conditional')));
  });

  test(
    'package filter limits findings while sibling references still count',
    () async {
      workspace.write(
        'pubspec.yaml',
        "name: app\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\nworkspace: [packages/core, packages/other]\n",
      );
      for (final name in ['core', 'other']) {
        workspace.write(
          'packages/$name/pubspec.yaml',
          "name: $name\nresolution: workspace\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n",
        );
        workspace.write(
          'packages/$name/lib/api.dart',
          'void save() {}\nvoid dead() {}\n',
        );
      }
      workspace.write(
        'bin/main.dart',
        "import 'package:core/api.dart';\nvoid main() => save();\n",
      );
      configurePackages({
        'app': '.',
        'core': 'packages/core',
        'other': 'packages/other',
      });
      final result = await KarekiRunner().analyze(
        request(packages: {'core', 'other'}),
      );
      final deadSaves = result.findings.where(
        (f) => f.ruleId == RuleId.unusedElement && f.message.contains("'save'"),
      );
      expect(deadSaves.single.packageName, 'other');
      expect(result.packagesAnalyzed, 2);
      expect(result.findings.every((f) => f.packageName != 'app'), isTrue);
    },
  );

  test(
    'resolution errors are explicit and cannot overwrite a baseline',
    () async {
      workspace.write(
        'lib/broken.dart',
        "import 'package:missing/api.dart';\nvoid broken() => missing();\n",
      );
      expect(analyze, throwsA(isA<ResolvedAnalysisException>()));
      workspace.write('baseline.json', 'preserve this content');
      final code = await runCli([
        '--root',
        workspace.path,
        '--baseline',
        'baseline.json',
        '--write-baseline',
      ], workingDirectory: workspace.path);
      expect(code, 2);
      expect(
        File(p.join(workspace.path, 'baseline.json')).readAsStringSync(),
        'preserve this content',
      );
    },
  );

  test(
    'missing bootstrap fails resolved mode but non-graph rules still run',
    () async {
      File(
        p.join(workspace.path, '.dart_tool', 'package_config.json'),
      ).deleteSync();
      await expectLater(analyze, throwsA(isA<ResolvedAnalysisException>()));
      final result = await KarekiRunner().analyze(
        request(rules: {RuleId.unusedFile}),
      );
      expect(result.packagesAnalyzed, 1);
    },
  );

  test('run and analyze both resolve declaration identities', () async {
    final result = await KarekiRunner().run(request());
    expect(
      result.findings.map((f) => f.stableId),
      (await analyze()).findings.map((f) => f.stableId),
    );
  });

  test('default resolution, suppression and stable baseline IDs', () async {
    workspace.write('lib/unique.dart', 'void uniqueDead() {}\n');
    workspace.write('kareki-config.yaml', '');
    final result = await analyze();
    final shared = result.findings.firstWhere(
      (f) => f.message.contains("'uniqueDead'"),
    );
    expect(shared.stableId, contains('uniqueDead'));
    expect(
      await runCli([
        '--root',
        workspace.path,
      ], workingDirectory: workspace.path),
      1,
    );
    expect(
      await runCli([
        'doctor',
        '--root',
        workspace.path,
      ], workingDirectory: workspace.path),
      0,
    );
    workspace.write('lib/api.dart', '''
class A { void save() {} }
class B {
  // kareki: ignore=unused_element
  void save() {}
}
''');
    expect(unused(await analyze()), isNot(contains(contains("'B.save'"))));
    workspace.write('kareki-config.yaml', 'analysis_mode: invalid\n');
    expect(
      await runCli([
        '--root',
        workspace.path,
      ], workingDirectory: workspace.path),
      64,
    );
  });
}
