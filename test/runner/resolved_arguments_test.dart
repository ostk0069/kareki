import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/cli/cli.dart';
import 'package:kareki/src/cli/doctor_cli.dart';
import 'package:kareki/src/doctor/doctor_finding.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:kareki/src/entry_points/entry_point_resolver.dart';
import 'package:kareki/src/reachability/resolved_reachability.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_resolved_arguments_');
    workspace.writePubspec(name: 'app');
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'app',
            'rootUri': Uri.directory(workspace.path).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
      }),
    );
  });
  tearDown(() => workspace.dispose());

  void source(String api, String main) {
    workspace.write('lib/api.dart', api);
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart';\nvoid main() { $main }\n",
    );
  }

  Future<RunResult> analyze() => KarekiRunner().analyze(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: {RuleId.unusedParameterOptional},
    ),
  );
  DoctorRequest doctorRequest() => DoctorRequest(
    rootPath: workspace.path,
    config: KarekiConfig.load(workspace.path),
  );
  Iterable<String> messages(RunResult result) =>
      result.findings.map((f) => f.message);

  test('empty resolved inputs have no inferred asset dependencies', () async {
    final result = await ResolvedReachability.build(
      files: [],
      generatedPaths: {},
      entryPoints: EntryPointSet(entryPointPaths: {}, keepAliveAnnotations: {}),
      config: KarekiConfig.defaults(),
      packageRoots: {},
      trackAssets: true,
    );
    expect(result.assetDependencies, isEmpty);
  });

  test(
    'runtime entry arguments are supplied but member homonyms are not',
    () async {
      workspace.write('bin/main.dart', '''
void main([List<String> arguments = const []]) {
  print(arguments);
  Member().main();
}
class Member { void main([List<String> unused = const []]) {} }
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(messages(result), isNot(contains(contains("'arguments'"))));
      expect(messages(result), contains(contains("'unused'")));
      expect(result.findings, hasLength(1));
    },
  );

  test('named main parameters are not treated as runtime arguments', () async {
    workspace.write('bin/main.dart', 'void main({String? argument}) {}');
    expect(messages(await analyze()), contains(contains("'argument'")));
  });

  test(
    'optional argument states distinguish usage, scoped non-use and unknown',
    () async {
      source('''
void target({int? used, int? unknown}) {}
void closed({int? absent}) {}
''', 'target(used: 1); final callback = target; callback(); closed();');
      final files = [
        for (final name in ['lib/api.dart', 'bin/main.dart'])
          DeclarationCollector().collect(
            path: p.join(workspace.path, name),
            packageName: 'app',
            content: File(p.join(workspace.path, name)).readAsStringSync(),
          ),
      ];
      Future<ResolvedReachability> resolve({required bool track}) =>
          ResolvedReachability.build(
            files: files,
            generatedPaths: {},
            entryPoints: EntryPointSet(
              entryPointPaths: {p.join(workspace.path, 'bin/main.dart')},
              keepAliveAnnotations: {},
            ),
            config: KarekiConfig.defaults(),
            packageRoots: {'app': workspace.path},
            trackArguments: track,
          );
      final graph = await resolve(track: true);
      expect(
        {
          for (final e in graph.optionalArgumentStates.entries)
            e.key.name: e.value,
        },
        {
          'used': OptionalArgumentState.used,
          'unknown': OptionalArgumentState.unknown,
          'absent': OptionalArgumentState.unused,
        },
      );
      expect(
        (await resolve(track: false)).optionalArgumentStates.values,
        everyElement(OptionalArgumentState.unknown),
      );
      final result = await analyze();
      expect(messages(result), [contains("'absent'")]);
      expect(
        result.analysisWarnings.single,
        contains('Unproven parameters: named unknown'),
      );
    },
  );

  test(
    'immediate generic extension callbacks prove omitted optional arguments',
    () async {
      source('''
extension Scope<T> on T { R let<R>(R Function(T) transform) => transform(this); }
String decode(int data, [int registry = 0]) => data.toString() + registry.toString();
''', 'print(1.let(decode));');
      final result = await analyze();
      expect(messages(result), [
        contains("'registry'"),
      ], reason: result.analysisWarnings.join('\n'));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'closed named callbacks provide usage proof even alongside another escape',
    () async {
      source('''
void target({int? used, int? missing}) {}
void consume({required void Function({int? used}) callback}) { callback.call(used: 1); }
''', 'consume(callback: (target)); final escaped = target; escaped();');
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(
        result.analysisWarnings.single,
        contains('Unproven parameters: named missing'),
      );
    },
  );

  test(
    'constructor tearoffs and implicit callables use exact static consumers',
    () async {
      source('''
class Product { Product.make(int data, [int registry = 0]) { print(registry); } }
class Callable { void call(int data, [int extra = 0]) {} }
class Consumer { static void consume(Object? Function(int) fn) { fn(1); } }
void invoke(void Function(int) fn) { fn(1); }
''', 'Consumer.consume(Product.make); invoke(Callable());');
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'registry'"), contains("'extra'")]),
        reason: result.analysisWarnings.join('\n'),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'any storage return forwarding mutation cast or capture prevents a proof',
    () async {
      final consumers = <String>[
        'saved = callback;',
        'return callback;',
        'forward(callback);',
        'callback = () {}; callback();',
        '(callback,) = (() {},); callback();',
        'for (callback in [() {}]) { callback(); }',
        'final local = () => callback(); local();',
        '(callback as dynamic)(value: 1);',
        'Function.apply(callback, [], {#value: 1});',
        'final alias = callback; alias();',
        'final tearoff = callback.call; tearoff();',
      ];
      for (final body in consumers) {
        source('''
Function? saved;
void target({int? value}) {}
void forward(Function fn) {}
Object? consume(void Function() callback) { $body return null; }
''', 'consume(target);');
        final result = await analyze();
        expect(result.findings, isEmpty, reason: body);
        expect(
          result.analysisWarnings.single,
          contains('target is uncertain'),
          reason: body,
        );
      }
    },
  );

  test('virtual asynchronous and dynamic consumers remain unknown', () async {
    for (final invocation in [
      'Base b = Child(); b.consume(target);',
      'asyncConsumer(target);',
      'dynamicConsumer(target);',
      'Future<void>.sync(target);',
    ]) {
      source('''
void target({int? value}) {}
class Base { void consume(void Function() callback) { callback(); } }
class Child extends Base { @override void consume(void Function() callback) { (callback as dynamic)(value: 1); } }
Future<void> asyncConsumer(void Function() callback) async { callback(); }
void dynamicConsumer(dynamic callback) { callback(); }
''', invocation);
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings.single, contains('target is uncertain'));
    }
  });

  test(
    'doctor uses immediate callback proofs without discarding valid suppressions',
    () async {
      source('''
void target({int? used, int? absent}) { print(used); print(absent); }
void consume(void Function({int? used}) callback) { callback(used: 1); }
''', 'consume(target);');
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  parameter_names: [absent, used]\n',
      );
      final result = await DoctorRunner().analyze(doctorRequest());
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.map((f) => f.subject), ['used']);
    },
  );

  test(
    'same-name consumers and unrecognized value expressions cannot share proofs',
    () async {
      source(
        '''
void target({int? value}) {}
void safeTarget({int? extra}) {}
Function? saved;
class Safe { static void consume(void Function() callback) { callback(); } }
class Unsafe { static void consume(void Function() callback) { saved = callback; } }
''',
        'Safe.consume(safeTarget); Unsafe.consume(target); Safe.consume(() => target());',
      );
      final result = await analyze();
      expect(messages(result), [
        contains("'extra'"),
      ], reason: result.analysisWarnings.join('\n'));
      expect(result.analysisWarnings.single, contains('target is uncertain'));
    },
  );

  test(
    'warnings identify unproven parameters and every function-value site',
    () async {
      source(
        '''
void target(int first, [int? used, int? missing]) {}
void named({int? used, int? missing}) {}
''',
        '''
target(0, 1); named(used: 1);
final a = target; final b = target; final c = named;
a(0); b(0); c();
''',
      );
      final result = await analyze();
      final positional = result.analysisWarnings.singleWhere(
        (w) => w.contains('target is uncertain'),
      );
      expect(
        positional,
        contains('Unproven parameters: positional 3 (missing)'),
      );
      expect(positional, contains('max positional 2'));
      expect(positional, contains('bin/main.dart:3:11'));
      expect(positional, contains('bin/main.dart:3:29'));
      expect(positional, contains('Function value:'));
      final named = result.analysisWarnings.singleWhere(
        (w) => w.contains('named is uncertain'),
      );
      expect(named, contains('Unproven parameters: named missing'));
      expect(named, contains('named used'));
      expect(result.findings, isEmpty);
      expect((await analyze()).analysisWarnings, result.analysisWarnings);
    },
  );

  test(
    'nullable calls and unused consumers map mixed argument positions',
    () async {
      source('''
void target({int? used, int? missing}) {}
void dropped({int? absent}) {}
void consume(int value, void Function({int? used})? callback, {required void Function() ignored}) {
  callback?.call(used: value);
}
''', 'consume(1, target, ignored: dropped);');
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'missing'"), contains("'absent'")]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'conditional cast and stored callback expressions stay protected',
    () async {
      source(
        '''
void target({int? value}) {}
void consume(void Function() callback) { callback(); }
''',
        'final condition = DateTime.now().second == 0; consume(condition ? target : target); consume(target as void Function());',
      );
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings.single, contains('target is uncertain'));
    },
  );

  test(
    'inferred function signatures do not prove the identity of a consumer',
    () async {
      source('''
void target({int? value}) {}
void safe(void Function() callback) { callback(); }
void unsafe(void Function() callback) { (callback as dynamic)(value: 1); }
''', 'var consumer = safe; consumer = unsafe; consumer(target);');
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings.single, contains('target is uncertain'));
    },
  );

  test('uncertainty evidence follows actual override relationships', () async {
    source('''
class Base { void save({int? value}) {} }
class Child implements Base { void save({int? value}) {} }
''', 'Base object = Child(); final callback = object.save; callback();');
    final result = await analyze();
    expect(result.analysisWarnings, hasLength(2));
    for (final warning in result.analysisWarnings) {
      expect(warning, contains('Unproven parameters: named value'));
      expect(warning, contains('Function value:'));
      expect(warning, contains('bin/main.dart:2:'));
    }
  });

  test(
    'super formals map named generic arguments without protecting unrelated parameters',
    () async {
      source('''
class Base<T> { Base.named(int first, {T? value, int? extra}) { print(value); print(extra); } }
class Middle<T> extends Base<T> { Middle.named({super.value}) : super.named(0); }
class Child extends Middle<int> { Child({super.value}) : super.named(); }
''', 'Child(value: 1);');
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'extra' of 'Base.named'")]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'positional super formals retain positions and inherited defaults',
    () async {
      source('''
class Base { Base(int requiredValue, [int forwarded = 1, int extra = 2]) { print(forwarded); print(extra); } }
class Child extends Base { Child(super.requiredValue, [super.renamed]); }
''', 'Child(0);');
      var result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'extra' of 'Base()'")]),
      );
      expect(result.analysisWarnings, isEmpty);
      workspace.write(
        'bin/main.dart',
        "import 'package:app/api.dart'; void main() { Child(0, 3); }",
      );
      result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'extra' of 'Base()'")]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'known named and positional usage settles unused-argument questions despite escapes',
    () async {
      source(
        '''
void named({int? a, int? b}) { print(a); print(b); }
void positional(int requiredValue, [int? a, int? b]) { print(a); print(b); }
''',
        '''
named(a: 1); named(b: 2); positional(0, 1, 2);
final n = named; n(); final p = positional; p(0);
''',
      );
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
      // A partially proven callable still protects its remaining parameters.
      workspace.write('bin/main.dart', '''
import 'package:app/api.dart';
void main() {
  named(a: 1); positional(0, 1);
  final n = named; n(); final p = positional; p(0);
}
''');
      final partial = await analyze();
      expect(partial.findings, isEmpty);
      expect(partial.analysisWarnings, hasLength(2));
      expect(
        partial.analysisWarnings,
        contains(contains('named is uncertain')),
      );
      expect(
        partial.analysisWarnings,
        contains(contains('positional is uncertain')),
      );
    },
  );

  test(
    'usage proofs propagate across real overrides before uncertainty is reported',
    () async {
      source(
        '''
abstract class Base { void save({int? value}); }
class Child implements Base { void save({int? value}) { print(value); } }
''',
        'Base instance = Child(); final fn = instance.save; fn(); Child().save(value: 1);',
      );
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'doctor can settle optional usage when every escaped parameter has direct evidence',
    () async {
      source(
        'void callback({int? value}) { print(value); }',
        'callback(value: 1); final fn = callback; fn();',
      );
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  parameter_names: [nonexistent]\n',
      );
      final result = await DoctorRunner().analyze(doctorRequest());
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.map((f) => f.subject), contains('nonexistent'));
    },
  );

  test(
    'null assertions cannot make homonymous constructor arguments uncertain',
    () async {
      source('''
class Used { final int? icon = 1; }
class Other { Other.icon({int? value}) { print(value); } }
''', 'print(Used().icon!); Other.icon();');
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'value' of 'Other.icon'")]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'built-in function call preserves real callbacks but not homonymous call methods',
    () async {
      source(
        '''
void callback({int? value}) { print(value); }
class Unrelated { void call({int? value}) { print(value); } }
class Callable { void call({int? value}) { print(value); } }
''',
        '''
final fn = callback;
fn.call(value: 1);
Callable().call(value: 1);
''',
      );
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'value' of 'Unrelated.call'")]),
      );
      expect(result.analysisWarnings, hasLength(1));
      expect(result.analysisWarnings.single, contains('callback is uncertain'));
    },
  );

  test('dynamic call still preserves same-name optional parameters', () async {
    source(
      'class Callable { void call({int? value}) {} }',
      'dynamic fn = Callable(); fn.call(value: 1);',
    );
    final result = await analyze();
    expect(result.findings, isEmpty);
    expect(
      result.analysisWarnings,
      contains(contains('Unresolved reference "call"')),
    );
    expect(result.analysisWarnings, contains(contains('call is uncertain')));
  });

  test(
    'show and hide do not escape functions while actual tear-offs still do',
    () async {
      source('''
void target({int? value}) { print(value); }
void hidden({int? value}) { print(value); }
void callback({int? value}) { print(value); }
''', 'target(); final fn = callback; fn(value: 1);');
      workspace.write(
        'lib/export.dart',
        "export 'api.dart' show target, callback;\nexport 'api.dart' hide hidden;\n",
      );
      workspace.write('bin/main.dart', '''
import 'package:app/export.dart' show target, callback;
import 'package:app/api.dart' hide hidden;
void main() { target(); final fn = callback; fn(value: 1); }
''');
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([
          contains("'value' of 'target'"),
          contains("'value' of 'hidden'"),
        ]),
      );
      expect(result.analysisWarnings, hasLength(1));
      expect(result.analysisWarnings.single, contains('callback is uncertain'));
    },
  );

  test(
    'record fields do not make same-name optional arguments uncertain',
    () async {
      source(
        '''
class A { void save({int? value}) { print(value); } }
void callback({int? value}) { print(value); }
''',
        '''
A().save();
final row = (save: callback,);
row.save(value: 1);
''',
      );
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'value' of 'A.save'")]),
      );
      expect(
        result.analysisWarnings,
        isNot(contains(contains('Unresolved reference "save"'))),
      );
      expect(
        result.analysisWarnings,
        isNot(contains(contains(' save is uncertain'))),
      );
      // The actual callback still escapes through the record value; its
      // parameter must not be reported unused on the basis of indirect calls.
      expect(
        result.analysisWarnings,
        contains(contains('callback is uncertain')),
      );
    },
  );

  test(
    'named and positional arguments distinguish same-name methods and generic substitutions',
    () async {
      source(
        '''
class A<T> { void save({T? value}) { print(value); } void send(int a, [int? extra]) { print(extra); } }
class B { void save({int? value}) { print(value); } void send(int a, [int? extra]) { print(extra); } }
''',
        'A<int>().save(value: 1); A<String>().save(); B().save(); A<int>().send(1, 2); B().send(1);',
      );
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([
          contains("'value' of 'B.save'"),
          contains("'extra' of 'B.send'"),
        ]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'constructors, dot shorthand, annotation and enum arguments resolve to exact declarations',
    () async {
      source('''
class A { A({int? value}) { print(value); } A.named({int? value}) { print(value); } }
class B { B({int? value}) { print(value); } B.named({int? value}) { print(value); } }
A build() => .new(value: 1);
A named() => .named(value: 1);
class Tag { final int? stored; const Tag({int? value}) : stored = value; }
@Tag(value: 1) void tagged() {}
enum Choice { one(value: 1); final int? stored; const Choice({int? value}) : stored = value; }
''', 'build(); named(); B(); B.named(); tagged(); print(Choice.one);');
      final result = await analyze();
      expect(
        messages(result),
        unorderedEquals([contains("'B()'"), contains("'B.named'")]),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'callable objects and parenthesized invocations preserve passed arguments',
    () async {
      source(
        '''
class Callable { void call({int? value}) { print(value); } }
void save({int? value}) { print(value); }
''',
        'final callable = Callable(); callable(value: 1); Callable()(value: 1); (save)(value: 1);',
      );
      expect((await analyze()).findings, isEmpty);
    },
  );

  test(
    'prefixes, parts, extensions and generated callers do not merge homonyms',
    () async {
      source(
        "part 'piece.dart';\nvoid save({int? value}) { print(value); }\nextension Ext on String { void send({int? value}) { print(value); } }",
        "'a'.send(value: 1);",
      );
      workspace.write(
        'lib/piece.dart',
        "part of 'api.dart';\nvoid fromPart({int? value}) { print(value); }",
      );
      workspace.write(
        'lib/other.dart',
        'void save({int? value}) { print(value); }',
      );
      workspace.write(
        'lib/client.g.dart',
        "import 'api.dart' as a;\nvoid generated() { a.save(value: 1); a.fromPart(value: 1); }",
      );
      final result = await analyze();
      expect(result.findings.single.filePath, endsWith('other.dart'));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'implicit callable tear-offs with closed consumers prove passed arguments',
    () async {
      source('''
class Callable { void call({int? value}) { print(value); } }
void consume(void Function({int? value}) callback) { callback(value: 1); }
''', 'consume(Callable());');
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'virtual dispatch propagates only within actual override families',
    () async {
      source('''
abstract class Contract { void save({int? value}); }
class A implements Contract { void save({int? value}) { print(value); } }
class B { void save({int? value}) { print(value); } }
''', 'Contract a = A(); a.save(value: 1); B().save();');
      expect(messages(await analyze()).single, contains("'B.save'"));
    },
  );

  test(
    'explicit super, redirect and redirecting factory calls preserve forwarded arguments',
    () async {
      source('''
class Base { Base({int? value}) { print(value); } }
class A extends Base { A() : super(value: 1); A.other() : this(); }
abstract class Factory { factory Factory({int? value}) = Target; }
class Target implements Factory { Target({int? value}) { print(value); } }
class B { B.named({int? value}) { print(value); } B() : this.named(value: 1); }
''', 'A.other(); Factory(value: 1); B();');
      expect((await analyze()).findings, isEmpty);
    },
  );

  test(
    'function, method and constructor tear-offs protect their own optional parameters',
    () async {
      source(
        '''
void callback({int? value}) { print(value); }
void untouched({int? value}) { print(value); }
class A { A.named({int? value}) { print(value); } void save({int? value}) { print(value); } }
''',
        'final f = callback; f(value: 1); final constructor = A.named; final a = constructor(); final method = a.save; method();',
      );
      final result = await analyze();
      expect(messages(result).single, contains("'untouched'"));
      expect(result.analysisWarnings, contains(contains('Argument usage')));
    },
  );

  test(
    'dynamic calls and super formals retain uncertain argument usage with warnings',
    () async {
      source('''
class Base { Base({int? value}) { print(value); } }
class A extends Base { A({super.value}); void save({int? value}) { print(value); } }
class B { void save({int? value}) { print(value); } }
''', 'dynamic a = A(value: 1); a.save();');
      final result = await analyze();
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, contains(contains('Argument usage')));
    },
  );

  test(
    'conditional alternatives never suggest removing platform-specific optional parameters',
    () async {
      source(
        "export 'stub.dart' if (dart.library.html) 'web.dart';",
        'save(value: 1);',
      );
      workspace.write(
        'lib/stub.dart',
        'void save({int? value}) { print(value); }',
      );
      workspace.write(
        'lib/web.dart',
        'void save({int? value}) { print(value); }',
      );
      expect((await analyze()).findings, isEmpty);
    },
  );

  test('optional-only mode still requires complete resolution', () async {
    source('void save({int? value}) {}', 'missing();');
    await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
  });

  test(
    'doctor uses resolved findings for parameter exclusions, directives and baseline staleness',
    () async {
      source('''
class A { void save({int? value}) { print(value); } }
class B { void save({int? value}) { print(value); } }
''', 'A().save(value: 1); B().save();');
      final findings = (await analyze()).findings;
      Baseline.write(
        p.join(workspace.path, 'baseline.json'),
        findings,
        rootPath: workspace.path,
      );
      workspace.write('kareki-config.yaml', 'baseline: baseline.json\n');
      var result = await DoctorRunner().analyze(doctorRequest());
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  parameter_names: [value, nonexistent]\n',
      );
      result = await DoctorRunner().analyze(doctorRequest());
      expect(result.findings.map((f) => f.subject), ['nonexistent']);
      workspace.write('kareki-config.yaml', '');
      workspace.write('lib/api.dart', '''
class A { void save({int? value}) { print(value); } }
class B {
  // kareki: ignore=unused_parameter_optional
  void save({int? value}) { print(value); }
}
''');
      expect((await DoctorRunner().analyze(doctorRequest())).findings, isEmpty);
    },
  );

  test(
    'doctor warns and skips semantic cleanup when usage is uncertain',
    () async {
      source(
        'void callback({int? value}) { print(value); }',
        'final f = callback; f();',
      );
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  parameter_names: [nonexistent]\n  files: [missing.g.dart]\n',
      );
      final result = await DoctorRunner().analyze(doctorRequest());
      expect(result.findings.map((f) => f.kind), [
        DoctorIssueKind.unusedExclude,
      ]);
      expect(
        result.analysisWarnings,
        contains(contains('Semantic doctor checks skipped')),
      );
      expect(
        await runCli([
          'doctor',
          '--root',
          workspace.path,
        ], workingDirectory: workspace.path),
        2,
      );
      workspace.write('kareki-config.yaml', '');
      expect(
        await runDoctor([
          '--root',
          workspace.path,
        ], workingDirectory: workspace.path),
        2,
      );
    },
  );

  test(
    'doctor recognizes simple-name directives for qualified method findings',
    () async {
      source('''
class A { void save() {} }
class B {
  // kareki: ignore=save
  void save() {}
}
''', 'A().save(); B();');
      expect((await DoctorRunner().analyze(doctorRequest())).findings, isEmpty);
    },
  );

  test(
    'doctor CLI rejects removed mode options and incomplete resolution',
    () async {
      source('void save({int? value}) { print(value); }', 'save(value: 1);');
      workspace.write('kareki-config.yaml', '');
      expect(
        await runCli([
          'doctor',
          '--root',
          workspace.path,
          '--format',
          'json',
        ], workingDirectory: workspace.path),
        0,
      );
      expect(
        await runDoctor([
          '--root',
          workspace.path,
          '--analysis-mode',
          'legacy',
        ], workingDirectory: workspace.path),
        64,
      );
      expect(
        await runCli([
          'doctor',
          '--root',
          workspace.path,
        ], workingDirectory: workspace.path),
        0,
      );
      workspace.write('baseline.json', 'do not change');
      workspace.write('lib/broken.dart', 'MissingType broken = MissingType();');
      expect(
        await runDoctor([
          '--root',
          workspace.path,
        ], workingDirectory: workspace.path),
        2,
      );
      expect(
        File(p.join(workspace.path, 'baseline.json')).readAsStringSync(),
        'do not change',
      );
    },
  );
}
