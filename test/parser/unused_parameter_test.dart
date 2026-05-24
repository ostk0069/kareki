import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

ParsedFile _parse(String source) => DeclarationCollector().collect(
  path: '/tmp/unused_parameter_test.dart',
  packageName: 'pkg',
  content: source,
);

List<String> _unusedParamNames(ParsedFile parsed, String declarationName) {
  final decl = parsed.declarations.firstWhere(
    (d) => d.name == declarationName,
  );
  return decl.unusedParameters.map((p) => p.name).toList();
}

void main() {
  group('DeclarationCollector.unusedParameters', () {
    test('flags a top-level function parameter never read in its body', () {
      final parsed = _parse('''
int compute(int a, int b) {
  return a + 1;
}
''');
      expect(_unusedParamNames(parsed, 'compute'), <String>['b']);
    });

    test(
      'flags both required and optional named parameters when not referenced',
      () {
        final parsed = _parse(r'''
String greet(String name, {required String title, String? suffix}) {
  return 'hi, $name';
}
''');
        expect(
          _unusedParamNames(parsed, 'greet'),
          containsAll(<String>['title', 'suffix']),
        );
      },
    );

    test('does not flag parameters referenced via expression body', () {
      final parsed = _parse('''
int square(int x) => x * x;
''');
      expect(_unusedParamNames(parsed, 'square'), isEmpty);
    });

    test('skips `_` and `__` placeholder parameters', () {
      final parsed = _parse('''
void onTap(int _, int __) {
  print('tapped');
}
''');
      expect(_unusedParamNames(parsed, 'onTap'), isEmpty);
    });

    test('skips methods annotated with @override', () {
      final parsed = _parse('''
class A {
  void doStuff(int x) {
    print(x);
  }
}

class B extends A {
  @override
  void doStuff(int x) {
    print('B');
  }
}
''');
      // `B.doStuff` is @override; its unused `x` must NOT be flagged.
      final bDoStuff = parsed.declarations.firstWhere(
        (d) => d.name == 'doStuff' && d.enclosingTypeName == 'B',
      );
      expect(bDoStuff.unusedParameters, isEmpty);
    });

    test('skips abstract methods (no body to inspect)', () {
      final parsed = _parse('''
abstract class Repo {
  void save(String key, int value);
}
''');
      final save = parsed.declarations.firstWhere((d) => d.name == 'save');
      expect(save.unusedParameters, isEmpty);
    });

    test('skips operator methods', () {
      final parsed = _parse('''
class Money {
  final int cents;
  const Money(this.cents);
  Money operator +(Money other) => Money(cents);
}
''');
      final plus = parsed.declarations.firstWhere(
        (d) =>
            d.name == '+' &&
            d.kind == DeclarationKind.method &&
            d.enclosingTypeName == 'Money',
        orElse: () => parsed.declarations.firstWhere(
          (d) => d.kind == DeclarationKind.method,
        ),
      );
      // Operator name retention varies by analyzer version; what matters
      // is that no parameter of an operator is flagged.
      expect(plus.unusedParameters, isEmpty);
    });

    test('skips `this.x` constructor parameters (field-formal)', () {
      final parsed = _parse('''
class Box {
  final int width;
  final int height;
  Box.dims(this.width, this.height);
}
''');
      final ctor = parsed.declarations.firstWhere((d) => d.name == 'dims');
      expect(ctor.unusedParameters, isEmpty);
    });

    test('skips `super.x` constructor parameters (super-formal)', () {
      final parsed = _parse('''
class Base {
  final int x;
  const Base(this.x);
}

class Child extends Base {
  Child.named(super.x);
}
''');
      final ctor = parsed.declarations.firstWhere((d) => d.name == 'named');
      expect(ctor.unusedParameters, isEmpty);
    });

    test('counts references from constructor initializers', () {
      final parsed = _parse('''
class Foo {
  final int v;
  Foo.checked(int raw)
      : assert(raw >= 0),
        v = raw;
}
''');
      final ctor = parsed.declarations.firstWhere((d) => d.name == 'checked');
      expect(ctor.unusedParameters, isEmpty);
    });

    test('flags an unused parameter in a named constructor', () {
      final parsed = _parse('''
class Foo {
  final int v;
  Foo.tagged(int raw, String tag) : v = raw;
}
''');
      final ctor = parsed.declarations.firstWhere((d) => d.name == 'tagged');
      expect(ctor.unusedParameters.map((p) => p.name).toList(), <String>['tag']);
    });

    test(
      'skips bodies that only `throw UnimplementedError(...)` '
      '(PlatformInterface stub idiom)',
      () {
        final parsed = _parse('''
abstract class GestureExclusion {
  Future<void> setRects(List<int> rects) {
    throw UnimplementedError('setRects has not been implemented.');
  }

  Future<void> clear(int token) =>
      throw UnimplementedError('clear has not been implemented.');
}
''');
        final setRects = parsed.declarations.firstWhere(
          (d) => d.name == 'setRects',
        );
        final clear = parsed.declarations.firstWhere(
          (d) => d.name == 'clear',
        );
        expect(setRects.unusedParameters, isEmpty);
        expect(clear.unusedParameters, isEmpty);
      },
    );

    test(
      'still flags params when body throws UnimplementedError alongside '
      'other statements (not a stub)',
      () {
        final parsed = _parse('''
void mixed(int used, int unusedX) {
  print(used);
  throw UnimplementedError();
}
''');
        final decl = parsed.declarations.firstWhere((d) => d.name == 'mixed');
        expect(
          decl.unusedParameters.map((p) => p.name).toList(),
          <String>['unusedX'],
        );
      },
    );

    test('records line and column of the flagged parameter name', () {
      final parsed = _parse('''
int compute(int a, int b) {
  return a;
}
''');
      final decl = parsed.declarations.firstWhere((d) => d.name == 'compute');
      final unused = decl.unusedParameters.single;
      expect(unused.name, 'b');
      expect(unused.line, 1);
      // Column points at the parameter name, not its type.
      expect(unused.column, greaterThan(1));
    });
  });
}
