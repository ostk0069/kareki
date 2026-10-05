import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  late TestWorkspace external;

  setUp(() {
    workspace = TestWorkspace.create('kareki_callback_app_');
    external = TestWorkspace.create('kareki_callback_dependency_');
    workspace.writePubspec(name: 'app');
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final value in config['packages'] as List<dynamic>)
            if ((value as Map<String, dynamic>)['name'] != 'kareki')
              {
                ...value,
                'rootUri': configFile.uri
                    .resolve(value['rootUri'] as String)
                    .toString(),
              },
          {
            'name': 'app',
            'rootUri': Uri.directory(workspace.path).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          {
            'name': 'consumer',
            'rootUri': Uri.directory(external.path).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
      }),
    );
    external.write('lib/api.dart', '''
Iterable<R> consume<R>(R Function(int) callback) sync* { yield callback(1); }
''');
  });

  tearDown(() {
    workspace.dispose();
    external.dispose();
  });

  Future<RunResult> analyze(String declarations, String body) {
    workspace.write('lib/api.dart', '''
import 'dart:collection';
import 'package:consumer/api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dartx/dartx.dart';
$declarations
void run() { $body }
''');
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart'; void main() => run();",
    );
    return KarekiRunner().analyze(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
        enabledRules: {RuleId.unusedParameterOptional},
      ),
    );
  }

  const target = 'int target(int value, {int optional = 0}) => optional;';
  const storedTarget = '''
int stored<T>(int context, int child, [int? page, bool barrier = true]) => page ?? 0;
''';
  const storedDependency = '''
import 'invoke.dart';
typedef Builder = int Function<T>(int context, int child, int page);
abstract class Type {
  factory Type.custom({Builder? builder}) = CustomType;
}
class CustomType implements Type {
  CustomType({this.builder});
  final Builder? builder;
}
class Route {
  Route({Builder? builder}) : type = Type.custom(builder: builder);
  final Type type;
}
''';
  void storedSources({
    String dependency = storedDependency,
    String? invocation,
  }) {
    external.write('lib/api.dart', dependency);
    external.write(
      'lib/invoke.dart',
      invocation ??
          '''
import 'api.dart';
int invoke(Type type) => type is CustomType && type.builder != null
    ? type.builder!.call<String>(1, 2, 3) : 0;
''',
    );
  }

  void expectProven(RunResult result) {
    expect(result.analysisWarnings, isEmpty);
    expect(result.findings.map((f) => f.message), [contains("'optional'")]);
  }

  void expectProtected(RunResult result) {
    expect(result.findings, isEmpty);
    expect(result.analysisWarnings.single, contains('target is uncertain'));
  }

  test(
    'workspace sync generator proves direct invocation, not a callback escape',
    () async {
      expectProven(
        await analyze('''
$target
Iterable<int> local(int Function(int) callback) sync* { yield callback(1); }
''', 'print(local(target).toList());'),
      );
    },
  );
  test(
    'external generic sync generator body is resolved without a name model',
    () async {
      expectProven(await analyze(target, 'print(consume(target).toList());'));
    },
  );
  test('real dartx mapNotNull proves constructor callback arguments', () async {
    expectProven(
      await analyze('''
class Product { Product.make(int value, {int optional = 0}) { print(optional); } }
''', 'print([1].mapNotNull(Product.make).toList());'),
    );
  });
  test(
    'external top-level static and extension consumers share the bounded proof',
    () async {
      external.write('lib/api.dart', '''
R consume<R>(R Function(int) callback) => callback(1);
class Consumer { static R run<R>(R Function(int) callback) => callback(1); }
extension Apply on int { R apply<R>(R Function(int) callback) => callback(this); }
''');
      expectProven(
        await analyze(
          target,
          'consume(target); Consumer.run(target); 1.apply(target);',
        ),
      );
    },
  );
  test(
    'external part declarations are resolved in their owning library',
    () async {
      external.write('lib/api.dart', "part 'body.dart';");
      external.write('lib/body.dart', '''
part of 'api.dart';
Iterable<R> consume<R>(R Function(int) callback) sync* { yield callback(1); }
''');
      expectProven(await analyze(target, 'consume(target);'));
    },
  );
  test(
    'external source changes are reanalyzed rather than trusting old approval',
    () async {
      expectProven(await analyze(target, 'consume(target);'));
      external.write('lib/api.dart', '''
Function? saved;
Iterable<R> consume<R>(R Function(int) callback) sync* {
  yield callback(1);
  saved = callback;
}
''');
      expectProtected(await analyze(target, 'consume(target);'));
    },
  );
  test(
    'generator storage yield forwarding aliases and captures remain unknown',
    () async {
      for (final body in [
        'yield callback;',
        'yield* [callback];',
        'saved = callback; yield callback(1);',
        'forward(callback); yield callback(1);',
        'final alias = callback; yield alias(1);',
        'final invoke = () => callback(1); yield invoke();',
        '(callback as dynamic)(1, optional: 7);',
        'callback = (int value) => 1; yield callback(1);',
      ]) {
        external.write('lib/api.dart', '''
Function? saved;
void forward(Function callback) {}
Iterable<Object?> consume(int Function(int) callback) sync* { $body }
''');
        expectProtected(await analyze(target, 'consume(target);'));
      }
    },
  );
  test(
    'external async native and invalid bodies cannot establish non-use',
    () async {
      for (final declaration in [
        'Future<void> consume(int Function(int) callback) async { callback(1); }',
        'Stream<int> consume(int Function(int) callback) async* { yield callback(1); }',
        'external void consume(int Function(int) callback);',
        'void consume(int Function(int) callback) { missing(); callback(1); }',
      ]) {
        external.write('lib/api.dart', declaration);
        expectProtected(await analyze(target, 'consume(target);'));
      }
    },
  );
  test(
    'same-named external consumers keep separate parameter identities',
    () async {
      external.write('lib/api.dart', '''
Function? saved;
class Safe { static void consume(int Function(int) callback) { callback(1); } }
class Unsafe { static void consume(int Function(int) callback) { saved = callback; } }
''');
      final result = await analyze('''
$target
int unknown(int value, {int extra = 0}) => extra;
''', 'Safe.consume(target); Unsafe.consume(unknown);');
      expect(result.findings.map((f) => f.message), [contains("'optional'")]);
      expect(result.analysisWarnings.single, contains('unknown is uncertain'));
    },
  );
  test(
    'resolved external calls retain actually supplied named arguments',
    () async {
      external.write('lib/api.dart', '''
Iterable<int> consume(int Function(int, {int used}) callback) sync* {
  yield callback(1, used: 7);
}
''');
      final result = await analyze('''
int target(int value, {int used = 0, int absent = 0}) => used + absent;
''', 'consume(target);');
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.map((f) => f.message), [contains("'absent'")]);
    },
  );
  test(
    'BuiltList map remains virtual even when a normal factory is visible',
    () async {
      expectProtected(
        await analyze(
          target,
          'BuiltList<int> values = BuiltList<int>([1]); values.map(target);',
        ),
      );
    },
  );
  test(
    'virtual receiver evidence follows static field declarations only',
    () async {
      final result = await analyze(
        '''
$target
class Cup { Cup(this.labels); final BuiltList<int> labels; }
class Race { Race(this.cup); final Cup cup; }
''',
        'final race = Race(Cup(BuiltList<int>([1]))); race.cup.labels.map(target);',
      );
      expectProtected(result);
      final warning = result.analysisWarnings.single;
      expect(warning, contains('consumer dispatch: virtual'));
      expect(warning, contains('static consumer: BuiltList.map at '));
      expect(warning, contains('consumer receiver type: BuiltList<int>'));
      expect(
        warning,
        contains(
          'receiver references (static only, leaf to root): Cup.labels at ',
        ),
      );
      expect(warning, contains(' <- Race.cup at '));
      expect(warning, contains(' <- race at '));
      expect(
        warning,
        contains('concrete receiver and callback forwarding are unproven'),
      );
    },
  );
  test(
    'virtual consumer diagnostics support named parentheses and cascades',
    () async {
      final result = await analyze(
        '''
$target
class Consumer { void apply({required int Function(int) callback}) { callback(1); } }
''',
        'final consumer = Consumer(); consumer.apply(callback: (target)); consumer..apply(callback: target);',
      );
      expectProtected(result);
      expect(
        'consumer dispatch: virtual'.allMatches(result.analysisWarnings.single),
        hasLength(2),
      );
      expect(
        'consumer receiver type: Consumer'.allMatches(
          result.analysisWarnings.single,
        ),
        hasLength(2),
      );
    },
  );
  test(
    'receiver diagnostics do not copy source literals or claim cast origins',
    () async {
      final result = await analyze('''
$target
BuiltList<int> load(String value) => BuiltList<int>([1]);
''', "(load('private-value') as Iterable<int>).map(target);");
      expectProtected(result);
      final warning = result.analysisWarnings.single;
      expect(warning, contains('consumer receiver type: Iterable<int>'));
      expect(warning, isNot(contains('private-value')));
      expect(warning, isNot(contains('receiver references')));
    },
  );
  test(
    'super consumers remain protected without being labeled virtual',
    () async {
      final result = await analyze('''
$target
class Base { void apply(int Function(int) callback) { callback(1); } }
class Child extends Base { void run() { super.apply(target); } }
''', 'Child().run();');
      expectProtected(result);
      expect(
        result.analysisWarnings.single,
        isNot(contains('consumer dispatch: virtual')),
      );
    },
  );
  test(
    'redirecting factories and copyWith can retain custom BuiltList receivers',
    () async {
      final result = await analyze(
        '''
$target
abstract class Cup {
  factory Cup(BuiltList<int> labels) = _Cup;
  BuiltList<int> get labels;
  Cup copyWith({required BuiltList<int> labels});
}
class _Cup implements Cup {
  _Cup(this.labels);
  @override final BuiltList<int> labels;
  @override Cup copyWith({required BuiltList<int> labels}) => Cup(labels);
}
class Race { Race(this.cup); final Cup cup; }
class OtherList extends IterableBase<int> implements BuiltList<int> {
  @override Iterator<int> get iterator => [1].iterator;
  @override Iterable<T> map<T>(T Function(int) callback) =>
    [(callback as dynamic)(1, optional: 7) as T];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
''',
        '''
final direct = Race(Cup(OtherList()));
print(direct.cup.labels.map(target).single);
final copied = Race(Cup(BuiltList<int>([1])).copyWith(labels: OtherList()));
print(copied.cup.labels.map(target).single);
''',
      );
      expectProtected(result);
      final run = await Process.run(Platform.resolvedExecutable, [
        '--packages=${p.join(workspace.path, '.dart_tool/package_config.json')}',
        p.join(workspace.path, 'bin/main.dart'),
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect((run.stdout as String).trim(), '7\n7');
    },
  );
  test(
    'a BuiltList implementation can really supply an optional callback argument',
    () async {
      final result = await analyze('''
$target
class OtherList extends IterableBase<int> implements BuiltList<int> {
  @override Iterator<int> get iterator => [1].iterator;
  @override Iterable<T> map<T>(T Function(int) callback) =>
    [(callback as dynamic)(1, optional: 7) as T];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
''', 'BuiltList<int> values = OtherList(); print(values.map(target).single);');
      expectProtected(result);
      final run = await Process.run(Platform.resolvedExecutable, [
        '--packages=${p.join(workspace.path, '.dart_tool/package_config.json')}',
        p.join(workspace.path, 'bin/main.dart'),
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect((run.stdout as String).trim(), '7');
    },
  );
  test(
    'stored constructor callback collects third argument but retains fourth',
    () async {
      storedSources();
      final result = await analyze('''
$storedTarget
class Child extends Route { Child() : super(builder: stored); }
''', 'Child();');
      expect(result.findings, isEmpty);
      final warning = result.analysisWarnings.single;
      expect(warning, contains('Unproven parameters: positional 4 (barrier)'));
      expect(warning, isNot(contains('positional 3 (page)')));
      expect(warning, contains('max positional 3'));
      expect(warning, contains('potential field flow, not runtime execution'));
      expect(warning, contains('CustomType.builder:'));
      expect(warning, contains('/lib/invoke.dart:'));
    },
  );
  test(
    'stored field invocation arguments come from bodies, not typedefs',
    () async {
      storedSources(invocation: "import 'api.dart'; void ignore(Type type) {}");
      final result = await analyze(storedTarget, 'Route(builder: stored);');
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings.single, contains('positional 3 (page)'));
      expect(
        result.analysisWarnings.single,
        contains('positional 4 (barrier)'),
      );
      expect(
        result.analysisWarnings.single,
        isNot(contains('Callback invocation evidence')),
      );
    },
  );
  test(
    'stored named argument evidence keeps other escaped parameters unknown',
    () async {
      external.write('lib/api.dart', '''
class Consumer {
  Consumer(this.callback);
  final int Function({int used}) callback;
  int invoke() => callback(used: 1);
}
''');
      final result = await analyze(
        'int stored({int used = 0, int unknown = 0}) => used;',
        'Consumer(stored);',
      );
      expect(result.findings, isEmpty);
      expect(
        result.analysisWarnings.single,
        contains('Unproven parameters: named unknown'),
      );
      expect(result.analysisWarnings.single, contains('named used'));
    },
  );
  test(
    'stored evidence is conservative across instances and never proves non-use',
    () async {
      storedSources();
      final result = await analyze('''
$storedTarget
int other<T>(int a, int b, int c) => c;
''', 'Route(builder: stored); Route(builder: other);');
      expect(result.findings, isEmpty);
      expect(
        result.analysisWarnings.single,
        contains('positional 4 (barrier)'),
      );
    },
  );
  test(
    'stored constructor reassignment casts and captures invalidate transfers',
    () async {
      for (final body in [
        'builder = replacement; CustomType(builder: builder);',
        'CustomType(builder: builder); builder = replacement;',
        'CustomType(builder: builder as Builder);',
        'final run = () => CustomType(builder: builder); run();',
        '(builder,) = (replacement,); CustomType(builder: builder);',
      ]) {
        storedSources(
          dependency:
              '''
import 'invoke.dart';
typedef Builder = int Function<T>(int a, int b, int c);
abstract class Type {}
class CustomType implements Type { CustomType({this.builder}); final Builder? builder; }
int replacement<T>(int a, int b, int c) => 0;
class Route { Route({Builder? builder}) { $body } }
''',
        );
        final result = await analyze(storedTarget, 'Route(builder: stored);');
        expect(result.findings, isEmpty);
        expect(result.analysisWarnings.single, contains('positional 3 (page)'));
      }
    },
  );
  test(
    'same-named fields in unrelated owners do not exchange stored evidence',
    () async {
      external.write('lib/api.dart', '''
class Safe { Safe(this.callback); final int Function(int) callback; }
class Other {
  Other(this.callback);
  final int Function(int, {int optional}) callback;
  int invoke() => callback(1, optional: 7);
}
''');
      expectProtected(await analyze(target, 'Safe(target);'));
    },
  );
  test(
    'source changes and errors remove stored usage evidence on reanalysis',
    () async {
      storedSources();
      expect(
        (await analyze(
          storedTarget,
          'Route(builder: stored);',
        )).analysisWarnings.single,
        isNot(contains('positional 3 (page)')),
      );
      for (final invocation in [
        "import 'api.dart'; void ignore(Type type) {}",
        "import 'api.dart'; void invoke(CustomType type) { missing(); type.builder!.call<int>(1, 2, 3); }",
      ]) {
        storedSources(invocation: invocation);
        final result = await analyze(storedTarget, 'Route(builder: stored);');
        expect(result.analysisWarnings.single, contains('positional 3 (page)'));
      }
    },
  );
  test(
    'mutable fields and explicit getters are not stored callback evidence',
    () async {
      for (final declaration in [
        'class Consumer { Consumer(this.callback); int Function(int, {int optional}) callback; int invoke() => callback(1, optional: 7); }',
        'class Consumer { Consumer(int Function(int, {int optional}) callback); int Function(int, {int optional}) get callback => other; int invoke() => callback(1, optional: 7); } int other(int a, {int optional = 0}) => a;',
      ]) {
        external.write('lib/api.dart', declaration);
        expectProtected(await analyze(target, 'Consumer(target);'));
      }
    },
  );
  test(
    'all potentially supplied arguments are retained without an uncertainty warning',
    () async {
      external.write('lib/api.dart', '''
class Consumer {
  Consumer(this.callback);
  final int Function(int, {int optional}) callback;
  int invoke() => callback(1, optional: 7);
}
''');
      final result = await analyze(target, 'Consumer(target);');
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );
  test(
    'stored workspace constructors remain outside the external field flow',
    () async {
      final result = await analyze('''
$target
class Consumer {
  Consumer(this.callback);
  final int Function(int, {int optional}) callback;
  int invoke() => callback(1, optional: 7);
}
''', 'Consumer(target);');
      expectProtected(result);
    },
  );
  test('stored dependency scan budget fails conservatively', () async {
    final exports = StringBuffer();
    for (var index = 0; index < 129; index++) {
      external.write('lib/extra$index.dart', 'const value$index = $index;');
      exports.writeln("export 'extra$index.dart';");
    }
    storedSources(dependency: '$exports\n$storedDependency');
    final result = await analyze(storedTarget, 'Route(builder: stored);');
    expect(result.findings, isEmpty);
    expect(result.analysisWarnings.single, contains('positional 3 (page)'));
    expect(
      result.analysisWarnings.single,
      isNot(contains('Callback invocation evidence')),
    );
  });
  test(
    'positional redirects super forwarding and part calls preserve identity',
    () async {
      external.write('lib/api.dart', '''
part 'part.dart';
typedef Builder = int Function(int, {int optional});
abstract class Route { factory Route(int ignored, Builder builder) = Child; }
class Base { Base(int ignored, this.callback); final Builder callback; }
class Child extends Base implements Route { Child(int ignored, Builder builder) : super(ignored, builder); }
''');
      external.write('lib/part.dart', '''
part of 'api.dart';
void noop() {}
int invoke(Base value) {
  noop();
  (value.callback).call(1, optional: 7);
  return (value).callback(1, optional: 7);
}
''');
      final result = await analyze(target, 'Route(0, target);');
      expect(result.findings, isEmpty);
      expect(result.analysisWarnings, isEmpty);
    },
  );
}
