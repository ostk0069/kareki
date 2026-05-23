import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:test/test.dart';

ParsedFile _parse(String source) => DeclarationCollector().collect(
  path: '/tmp/ignore_test.dart',
  packageName: 'pkg',
  content: source,
);

void main() {
  group('file-level `// kareki: ignore_for_file=...` parsing', () {
    test('rule name on its own line is collected', () {
      final parsed = _parse('''
// kareki: ignore_for_file=test_only_used
// Suppression rationale: see ADR-12.

import 'package:foo/foo.dart';

class Thing {}
''');
      expect(parsed.fileLevelIgnores, contains('test_only_used'));
    });

    test(
      'directive followed by a blank line then import is still collected',
      () {
        final parsed = _parse('''
// kareki: ignore_for_file=test_only_used

import 'package:foo/foo.dart';

class Thing {}
''');
        expect(
          parsed.fileLevelIgnores,
          contains('test_only_used'),
          reason:
              'WINTICKET learning (2026-05-23) claimed this placement did not '
              'work. If this test passes, the learning was a misdiagnosis.',
        );
      },
    );

    test('directive at end of file is collected', () {
      final parsed = _parse('''
import 'package:foo/foo.dart';

class Thing {}

// kareki: ignore_for_file=unused_element
''');
      expect(parsed.fileLevelIgnores, contains('unused_element'));
    });

    test('multiple rules in a single directive are split on comma', () {
      final parsed = _parse('''
// kareki: ignore_for_file=test_only_used, unused_element

class Thing {}
''');
      expect(
        parsed.fileLevelIgnores,
        containsAll(<String>['test_only_used', 'unused_element']),
      );
    });

    test('symbol names can be listed alongside rule ids', () {
      final parsed = _parse('''
// kareki: ignore_for_file=xApiKey

class Thing {}
''');
      expect(parsed.fileLevelIgnores, contains('xApiKey'));
    });

    test('directive on a line without `// kareki:` prefix is ignored', () {
      final parsed = _parse('''
// ignore_for_file: unused_element
// dart format off

class Thing {}
''');
      expect(parsed.fileLevelIgnores, isEmpty);
    });
  });
}
