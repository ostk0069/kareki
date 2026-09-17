import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

ParsedFile _parse(String source) => DeclarationCollector().collect(
  path: '/tmp/language_compatibility_test.dart',
  packageName: 'pkg',
  content: source,
);

void main() {
  group('Dart 3.13 primary constructors', () {
    test('collects the constructor and declaring fields', () {
      final parsed = _parse('''
class Point(final int x, int input, {var String? label, int? optional}) {
  final int doubled = input * 2;
  this : assert(input >= 0) {}
}
''');

      final constructor = parsed.declarations.firstWhere(
        (declaration) =>
            declaration.kind == DeclarationKind.constructor &&
            declaration.name == 'Point',
      );
      final fields = parsed.declarations
          .where((declaration) => declaration.kind == DeclarationKind.field)
          .map((declaration) => declaration.name);

      expect(fields, containsAll(<String>['x', 'label', 'doubled']));
      expect(
        constructor.optionalParameters.map((parameter) => parameter.name),
        ['optional'],
        reason: 'declaring parameters behave as fields, not optional params',
      );
      expect(constructor.outgoingNames, contains('input'));
    });

    test('analyzes normal parameters in a named primary constructor', () {
      final parsed = _parse('''
class Service.named(final int id, int used, int unused) {
  final int value = used;
}
''');

      final constructor = parsed.declarations.firstWhere(
        (declaration) =>
            declaration.kind == DeclarationKind.constructor &&
            declaration.name == 'named',
      );

      expect(
        constructor.unusedParameters.map((parameter) => parameter.name),
        ['unused'],
      );
    });

    test('records enum constant calls for optional parameter usage', () {
      final parsed = _parse('''
enum Status({int? code, int? unused}) {
  active(code: 1),
  inactive();
}
''');

      final constructor = parsed.declarations.firstWhere(
        (declaration) =>
            declaration.kind == DeclarationKind.constructor &&
            declaration.name == 'Status',
      );

      expect(
        constructor.optionalParameters.map((parameter) => parameter.name),
        containsAll(<String>['code', 'unused']),
      );
      expect(parsed.callSiteUsage['Status']?.namedArgsPassed, {'code'});
    });

    test('collects a bodyless primary constructor', () {
      final parsed = _parse('class const Marker();');

      expect(
        parsed.declarations,
        contains(
          isA<DeclarationRecord>()
              .having((d) => d.kind, 'kind', DeclarationKind.constructor)
              .having((d) => d.name, 'name', 'Marker'),
        ),
      );
    });

    test('collects named extension type primary constructors', () {
      final parsed = _parse('''
extension type const Token.named(int value) {
  this : assert(value >= 0);
}
''');

      expect(
        parsed.declarations,
        contains(
          isA<DeclarationRecord>()
              .having((d) => d.kind, 'kind', DeclarationKind.constructor)
              .having((d) => d.name, 'name', 'named')
              .having((d) => d.enclosingTypeName, 'enclosing type', 'Token'),
        ),
      );
    });
  });

  test('Dart 3.13 concise constructors keep their declared names', () {
    final parsed = _parse('''
class Cache() {
  new named(int value) {}
  factory cached(int value) = Cache.named;
}
''');

    final constructors = parsed.declarations
        .where((declaration) => declaration.kind == DeclarationKind.constructor)
        .map((declaration) => declaration.name);

    expect(constructors, containsAll(<String>['Cache', 'named', 'cached']));
  });

  group('Dart 3.10 dot shorthands', () {
    test('collects property, method, and constructor references', () {
      final parsed = _parse('''
enum Status { active }

class Client {
  Client.named({String? endpoint});
}

Status status = .active;
int number = .parse('42');
Client client = .named(endpoint: 'localhost');
Client defaultClient = .new(endpoint: 'default');
''');

      expect(
        parsed.topLevelIdentifierReferences,
        containsAll(<String>['active', 'parse', 'named']),
      );
      expect(parsed.callSiteUsage['parse']?.maxPositionalArgs, 1);
      expect(parsed.callSiteUsage['named']?.namedArgsPassed, {'endpoint'});
      expect(
        parsed.callSiteUsage['.new']?.namedArgsPassed,
        {'endpoint'},
      );
    });

    test('does not invent call-site usage for property access', () {
      final parsed = _parse('''
enum Status { active }
Status status = .active;
''');

      expect(parsed.callSiteUsage, isNot(contains('active')));
    });
  });

  test('Dart 3.12 private named initializing formals are exempt', () {
    final parsed = _parse('''
class Point {
  final int _x;
  Point({required this._x});
}

Point makePoint() => Point(x: 1);
''');
    final constructor = parsed.declarations.firstWhere(
      (declaration) =>
          declaration.kind == DeclarationKind.constructor &&
          declaration.name == 'Point',
    );

    expect(constructor.unusedParameters, isEmpty);
    expect(constructor.optionalParameters, isEmpty);
    expect(parsed.callSiteUsage['Point']?.namedArgsPassed, {'x'});
  });

  test('collects extension types and their members', () {
    final parsed = _parse('''
extension type UserId(int value) {
  String format() => value.toString();
}
''');

    expect(
      parsed.declarations,
      contains(
        isA<DeclarationRecord>()
            .having((d) => d.name, 'name', 'UserId')
            .having(
              (d) => d.kind,
              'kind',
              DeclarationKind.extensionDecl,
            ),
      ),
    );
    expect(
      parsed.declarations,
      contains(
        isA<DeclarationRecord>()
            .having((d) => d.name, 'name', 'format')
            .having((d) => d.enclosingTypeName, 'enclosing type', 'UserId'),
      ),
    );
  });

  test('collects class aliases and their referenced types', () {
    final parsed = _parse('''
class Base {}
mixin Feature {}
class Service = Base with Feature;
''');
    final alias = parsed.declarations.firstWhere(
      (declaration) => declaration.name == 'Service',
    );

    expect(alias.kind, DeclarationKind.classDecl);
    expect(alias.outgoingNames, containsAll(<String>['Base', 'Feature']));
  });

  test('collects references from records and patterns', () {
    final parsed = _parse('''
class Target {}

Target unwrap((Target, int) record) {
  final (target, _) = record;
  return target;
}
''');
    final unwrap = parsed.declarations.firstWhere(
      (declaration) => declaration.name == 'unwrap',
    );

    expect(unwrap.outgoingNames, contains('Target'));
  });

  test('does not throw for a syntactically incomplete source file', () {
    expect(() => _parse('class Broken { void run('), returnsNormally);
  });
}
