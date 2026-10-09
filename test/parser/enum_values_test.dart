import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

void main() {
  test(
    'collects enhanced enum constants with host, tokens and annotations',
    () {
      const source = '''
@Keep()
enum Status {
  @ValueKeep() active(1),
  _hidden(2);
  const Status(this.code);
  final int code;
}
''';
      final parsed = DeclarationCollector().collect(
        path: '/tmp/enums.dart',
        packageName: 'app',
        content: source,
      );
      final values = parsed.declarations
          .where((d) => d.kind == DeclarationKind.enumConstant)
          .toList();
      expect(values.map((d) => d.name), ['active', '_hidden']);
      expect(values.map((d) => d.enclosingTypeName), ['Status', 'Status']);
      final active = values.first;
      expect(active.annotations, {'Keep', 'ValueKeep'});
      expect(active.isPublic, isTrue);
      expect(active.line, 3);
      expect(active.column, 16);
      expect(active.length, 6);
      expect(
        source.substring(active.offset, active.offset + active.length),
        'active',
      );
      expect(values.last.annotations, {'Keep'});
      expect(values.last.isPublic, isFalse);
      expect(values.map((d) => d.stableId).toSet(), hasLength(2));
      expect(parsed.declarations.where((d) => d.name == 'code'), hasLength(1));
    },
  );
}
