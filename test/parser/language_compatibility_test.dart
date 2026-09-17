import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

ParsedFile _parse(String source) => DeclarationCollector().collect(
  path: '/tmp/language_compatibility_test.dart',
  packageName: 'pkg',
  content: source,
);

void main() {
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
