import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

ParsedFile _parse(String source) => DeclarationCollector().collect(
  path: '/tmp/unused_parameter_optional_test.dart',
  packageName: 'pkg',
  content: source,
);

List<String> _optionalNames(ParsedFile parsed, String declarationName) {
  final decl = parsed.declarations.firstWhere((d) => d.name == declarationName);
  return decl.optionalParameters.map((p) => p.name).toList();
}

void main() {
  group('DeclarationCollector.optionalParameters', () {
    test('collects named optional params and marks them as named', () {
      final parsed = _parse('''
String greet({String? title, String? suffix}) {
  return title.toString() + suffix.toString();
}
''');
      final decl = parsed.declarations.firstWhere((d) => d.name == 'greet');
      expect(decl.optionalParameters.map((p) => p.name).toList(), [
        'title',
        'suffix',
      ]);
      for (final p in decl.optionalParameters) {
        expect(p.isNamed, isTrue);
        expect(p.positionalIndex, isNull);
      }
    });

    test('collects positional optional params with their indices', () {
      final parsed = _parse('''
String fmt(int required, [int? second, int? third]) {
  return required.toString() + second.toString() + third.toString();
}
''');
      final decl = parsed.declarations.firstWhere((d) => d.name == 'fmt');
      expect(decl.optionalParameters.map((p) => p.name).toList(), [
        'second',
        'third',
      ]);
      final second = decl.optionalParameters[0];
      final third = decl.optionalParameters[1];
      expect(second.isNamed, isFalse);
      expect(second.positionalIndex, 1);
      expect(third.isNamed, isFalse);
      expect(third.positionalIndex, 2);
    });

    test(
      'skips `this.x` and `super.x` optional params (field/super formal)',
      () {
        final parsed = _parse('''
class Box {
  final int width;
  final int height;
  Box({this.width = 1, this.height = 2});
}

class Child extends Box {
  Child({super.width, super.height});
}
''');
        // Both unnamed constructors are emitted under the class's simple
        // name. Neither should record `this.x` / `super.x` as optional.
        final box = parsed.declarations.firstWhere(
          (d) => d.kind == DeclarationKind.constructor && d.name == 'Box',
        );
        expect(box.optionalParameters, isEmpty);
        final child = parsed.declarations.firstWhere(
          (d) => d.kind == DeclarationKind.constructor && d.name == 'Child',
        );
        expect(child.optionalParameters, isEmpty);
      },
    );

    test('skips `@override` callables (signature is contractual)', () {
      final parsed = _parse('''
class A {
  void apply({int? x}) => print(x);
}

class B extends A {
  @override
  void apply({int? x}) => print('B');
}
''');
      final b = parsed.declarations.firstWhere(
        (d) => d.name == 'apply' && d.enclosingTypeName == 'B',
      );
      expect(b.optionalParameters, isEmpty);
    });

    test('skips abstract methods (no body) and UnimplementedError stubs', () {
      final parsed = _parse('''
abstract class Repo {
  void save({String? key});

  Future<void> open({String? url}) {
    throw UnimplementedError('not implemented');
  }
}
''');
      expect(_optionalNames(parsed, 'save'), isEmpty);
      expect(_optionalNames(parsed, 'open'), isEmpty);
    });

    test('records an unnamed constructor under the class simple name', () {
      final parsed = _parse('''
class Service {
  Service({String? endpoint}) : _endpoint = endpoint;
  final String? _endpoint;
}
''');
      final ctor = parsed.declarations.firstWhere(
        (d) => d.kind == DeclarationKind.constructor && d.name == 'Service',
      );
      expect(ctor.optionalParameters.map((p) => p.name).toList(), ['endpoint']);
      // unnamed constructors deliberately leave `unusedParameters`
      // empty to preserve the previous `unused_parameter` scope.
      expect(ctor.unusedParameters, isEmpty);
    });
  });

  group('DeclarationCollector.callSiteUsage', () {
    test('records named arguments passed at MethodInvocation call sites', () {
      final parsed = _parse('''
void main() {
  doWork(host: 'x', port: 1);
  doWork(host: 'y');
}
''');
      final usage = parsed.callSiteUsage['doWork'];
      expect(usage, isNotNull);
      expect(usage!.namedArgsPassed, {'host', 'port'});
      expect(usage.maxPositionalArgs, 0);
    });

    test('records max positional arg count across calls', () {
      final parsed = _parse('''
void main() {
  fmt(1);
  fmt(1, 2);
  fmt(1, 2, 3);
}
''');
      final usage = parsed.callSiteUsage['fmt'];
      expect(usage, isNotNull);
      expect(usage!.maxPositionalArgs, 3);
    });

    test('records constructor calls under the constructor simple name', () {
      final parsed = _parse('''
void main() {
  Service.create(tag: 'a');
  HttpClient(endpoint: 'b');
}
''');
      final ctor = parsed.callSiteUsage['create'];
      expect(ctor, isNotNull);
      expect(ctor!.namedArgsPassed, {'tag'});

      final unnamed = parsed.callSiteUsage['HttpClient'];
      expect(unnamed, isNotNull);
      expect(unnamed!.namedArgsPassed, {'endpoint'});
    });
  });
}
