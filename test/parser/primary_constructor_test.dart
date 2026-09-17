import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

ParsedFile _parse(String source) => DeclarationCollector().collect(
  path: '/tmp/primary_constructor_test.dart',
  packageName: 'pkg',
  content: source,
);

void main() {
  group('primary constructors', () {
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

    test('collects a bodyless const primary constructor', () {
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

    test('keeps concise constructor names', () {
      final parsed = _parse('''
class Cache() {
  new named(int value) {}
  factory cached(int value) = Cache.named;
}
''');

      final constructors = parsed.declarations
          .where(
            (declaration) => declaration.kind == DeclarationKind.constructor,
          )
          .map((declaration) => declaration.name);

      expect(constructors, containsAll(<String>['Cache', 'named', 'cached']));
    });
  });
}
