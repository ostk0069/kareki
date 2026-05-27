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

  group('per-line `// kareki: ignore=...` parsing', () {
    test('standalone comment targets the next code line', () {
      final parsed = _parse('''
class Thing {}

// kareki: ignore=unused_element
class Other {}
''');
      // `class Other` is on line 4 (1-based).
      expect(parsed.lineLevelIgnores[4], contains('unused_element'));
    });

    test(
      'standalone comment skips blank and comment-only lines to the next code',
      () {
        final parsed = _parse('''
// kareki: ignore=unused_element
// some doc explaining why

class Skipped {}
''');
        // `class Skipped` is on line 4.
        expect(parsed.lineLevelIgnores[4], contains('unused_element'));
      },
    );

    test('trailing comment targets its own line', () {
      final parsed = _parse('''
class Thing {} // kareki: ignore=unused_element
''');
      expect(parsed.lineLevelIgnores[1], contains('unused_element'));
    });

    test('multiple names in a single directive are split on comma', () {
      final parsed = _parse('''
// kareki: ignore=unused_element, fooSymbol
class Thing {}
''');
      expect(
        parsed.lineLevelIgnores[2],
        containsAll(<String>['unused_element', 'fooSymbol']),
      );
    });

    test('directive without `// kareki:` prefix is ignored', () {
      final parsed = _parse('''
// ignore: unused_element
class Thing {}
''');
      expect(parsed.lineLevelIgnores, isEmpty);
    });

    test('`ignore_for_file=` directive is not also collected as line ignore',
        () {
      final parsed = _parse('''
// kareki: ignore_for_file=unused_element
class Thing {}
''');
      expect(parsed.lineLevelIgnores, isEmpty);
      expect(parsed.fileLevelIgnores, contains('unused_element'));
    });
  });
}
